# frozen_string_literal: true

require "mysql2"

module Multiwoven::Integrations::Source
  module MariaDB
    include Multiwoven::Integrations::Core
    class Client < SourceConnector
      def check_connection(connection_config)
        connection_config = connection_config.with_indifferent_access
        db = create_connection(connection_config)
        ConnectionStatus.new(status: ConnectionStatusType["succeeded"]).to_multiwoven_message
      rescue StandardError => e
        ConnectionStatus.new(status: ConnectionStatusType["failed"], message: e.message).to_multiwoven_message
      ensure
        db&.close
      end

      def discover(connection_config)
        connection_config = connection_config.with_indifferent_access
        query = "SELECT table_name, column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema = '#{connection_config[:database]}' ORDER BY table_name, ordinal_position;"
        db = create_connection(connection_config)
        results = query_execution(db, query)
        catalog = Catalog.new(streams: create_streams(results))
        catalog.to_multiwoven_message
      rescue StandardError => e
        handle_exception(e, {
                           context: "MARIA:DB:DISCOVER:EXCEPTION",
                           type: "error"
                         })
      ensure
        db&.close
      end

      def read(sync_config)
        connection_config = sync_config.source.connection_specification.with_indifferent_access
        query = sync_config.model.query
        query = batched_query(query, sync_config.limit, sync_config.offset) unless sync_config.limit.nil? && sync_config.offset.nil?
        db = create_connection(connection_config)
        query(db, query)
      rescue StandardError => e
        handle_exception(e, {
                           context: "MARIA:DB:READ:EXCEPTION",
                           type: "error",
                           sync_id: sync_config.sync_id,
                           sync_run_id: sync_config.sync_run_id
                         })
      ensure
        db&.close
      end

      private

      def create_connection(connection_config)
        client = Mysql2::Client.new(
          host: connection_config[:host],
          port: connection_config[:port],
          username: connection_config[:username],
          password: connection_config[:password],
          database: connection_config[:database],
          encoding: "utf8mb4",
          init_command: "SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci"
        )
        client
      end

      def query_execution(db, query)
        results = []
        db.query(query, symbolize_keys: true, as: :hash, cast_booleans: true).each do |row|
          # Ensure all string values are properly encoded as UTF-8
          row = row.transform_values do |value|
            value.is_a?(String) ? value.force_encoding(Encoding::UTF_8) : value
          end
          results << row
        end
        results
      end

      def create_streams(records)
        group_by_table(records).map do |_, r|
          Multiwoven::Integrations::Protocol::Stream.new(name: r[:tablename], action: StreamAction["fetch"], json_schema: convert_to_json_schema(r[:columns]))
        end
      end

      def query(db, query)
        query_execution(db, query).map do |row|
          RecordMessage.new(data: row, emitted_at: Time.now.to_i).to_multiwoven_message
        end
      end

      def group_by_table(records)
        result = {}
        records.each_with_index do |entry, index|
          table_name = entry[:table_name]
          column_data = {
            column_name: entry[:column_name],
            data_type: entry[:data_type],
            is_nullable: entry[:is_nullable] == "YES"
          }
          result[index] ||= {}
          result[index][:tablename] = table_name
          result[index][:columns] = [column_data]
        end
        result
      end
    end
  end
end
