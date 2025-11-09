# frozen_string_literal: true

require "cgi"
require_relative "schema_helper"
module Multiwoven
  module Integrations
    module Destination
      module Airtable
        include Multiwoven::Integrations::Core
        class Client < DestinationConnector
          prepend Multiwoven::Integrations::Core::RateLimiter
          MAX_CHUNK_SIZE = 10
          def check_connection(connection_config)
            connection_config = connection_config.with_indifferent_access
            bases = Multiwoven::Integrations::Core::HttpClient.request(
              AIRTABLE_BASES_ENDPOINT,
              HTTP_GET,
              headers: auth_headers(connection_config[:api_key])
            )
            if success?(bases)
              base_id_exists?(bases, connection_config[:base_id])
              success_status
            else
              failure_status(nil)
            end
          rescue StandardError => e
            failure_status(e)
          end

          def discover(connection_config)
            connection_config = connection_config.with_indifferent_access
            base_id = connection_config[:base_id]
            api_key = connection_config[:api_key]

            bases = Multiwoven::Integrations::Core::HttpClient.request(
              AIRTABLE_BASES_ENDPOINT,
              HTTP_GET,
              headers: auth_headers(api_key)
            )

            base = extract_bases(bases).find { |b| b["id"] == base_id }
            base_name = base["name"]

            schema = Multiwoven::Integrations::Core::HttpClient.request(
              AIRTABLE_GET_BASE_SCHEMA_ENDPOINT.gsub("{baseId}", base_id),
              HTTP_GET,
              headers: auth_headers(api_key)
            )

            catalog = build_catalog_from_schema(extract_body(schema), base_id, base_name)
            catalog.to_multiwoven_message
          rescue StandardError => e
            handle_exception(e, {
                               context: "AIRTABLE:DISCOVER:EXCEPTION",
                               type: "error"
                             })
          end

          def write(sync_config, records, action = "destination_insert")
            connection_config = sync_config.destination.connection_specification.with_indifferent_access
            api_key = connection_config[:api_key]
            url = sync_config.stream.url
            primary_key = sync_config.model.primary_key
            log_message_array = []
            write_success = 0
            write_failure = 0

            # Bulk query: Find all existing records in ONE request (instead of N requests)
            existing_records_map = find_existing_records_bulk(records, primary_key, url, api_key)

            records.each_slice(MAX_CHUNK_SIZE) do |chunk|
              # Separate into updates and inserts based on bulk query results
              updates = []
              inserts = []

              chunk.each do |record|
                pk_value = record[primary_key]
                if existing_records_map[pk_value]
                  # Record exists in Airtable - prepare for UPDATE
                  updates << { id: existing_records_map[pk_value], fields: record }
                else
                  # Record doesn't exist - prepare for INSERT
                  inserts << { fields: record }
                end
              end

              # Process updates with PATCH
              if updates.any?
                update_payload = create_payload_with_ids(updates)
                update_response = Multiwoven::Integrations::Core::HttpClient.request(
                  url,
                  "PATCH",
                  payload: update_payload,
                  headers: auth_headers(api_key)
                )
                if success?(update_response)
                  write_success += updates.size
                else
                  write_failure += updates.size
                end
                log_message_array << log_request_response("info", ["PATCH", url, update_payload], update_response)
              end

              # Process inserts with POST
              if inserts.any?
                insert_payload = create_payload_with_ids(inserts)
                insert_response = Multiwoven::Integrations::Core::HttpClient.request(
                  url,
                  HTTP_POST,
                  payload: insert_payload,
                  headers: auth_headers(api_key)
                )
                if success?(insert_response)
                  write_success += inserts.size
                else
                  write_failure += inserts.size
                end
                log_message_array << log_request_response("info", [HTTP_POST, url, insert_payload], insert_response)
              end
            rescue StandardError => e
              handle_exception(e, {
                                 context: "AIRTABLE:RECORD:WRITE:EXCEPTION",
                                 type: "error",
                                 sync_id: sync_config.sync_id,
                                 sync_run_id: sync_config.sync_run_id
                               })
              write_failure += chunk.size
              log_message_array << log_request_response("error", args, e.message)
            end
            tracking_message(write_success, write_failure, log_message_array)
          rescue StandardError => e
            handle_exception(e, {
                               context: "AIRTABLE:RECORD:WRITE:EXCEPTION",
                               type: "error",
                               sync_id: sync_config.sync_id,
                               sync_run_id: sync_config.sync_run_id
                             })
          end

          private

          def find_existing_records_bulk(records, primary_key, url, api_key)
            return {} if records.empty?

            # Build OR formula to find all records in a single query
            # Example: OR({id}='1', {id}='2', {id}='3')
            formulas = records.map do |record|
              pk_value = record[primary_key]
              escaped_value = pk_value.to_s.gsub("'", "\\'")
              "{#{primary_key}}='#{escaped_value}'"
            end

            # Airtable has a URL length limit, so batch queries if needed
            # Typically safe up to ~100 records per query
            existing_map = {}
            formulas.each_slice(100) do |formula_batch|
              formula = "OR(#{formula_batch.join(', ')})"
              encoded_formula = CGI.escape(formula)
              search_url = "#{url}?filterByFormula=#{encoded_formula}"

              response = Multiwoven::Integrations::Core::HttpClient.request(
                search_url,
                HTTP_GET,
                headers: auth_headers(api_key)
              )

              next unless success?(response)

              body = extract_body(response)
              airtable_records = body["records"] || []

              # Build map: primary_key_value => airtable_record_id
              airtable_records.each do |airtable_record|
                pk_value = airtable_record.dig("fields", primary_key)
                existing_map[pk_value] = airtable_record["id"] if pk_value
              end
            end

            existing_map
          rescue StandardError => e
            handle_exception(e, {
                               context: "AIRTABLE:BULK:FIND:EXCEPTION",
                               type: "error"
                             })
            {} # Return empty map on error - all records will be treated as inserts
          end

          def create_payload_with_ids(processed_records)
            {
              "records" => processed_records
            }
          end

          def create_payload(records)
            {
              "records" => records.map do |record|
                {
                  "fields" => record
                }
              end
            }
          end

          def base_id_exists?(bases, base_id)
            return if extract_bases(bases).any? { |base| base["id"] == base_id }

            raise ArgumentError, "base_id not found"
          end

          def extract_bases(response)
            response_body = extract_body(response)
            response_body["bases"] if response_body
          end

          def extract_body(response)
            response_body = response.body
            JSON.parse(response_body) if response_body
          end

          def load_catalog
            read_json(CATALOG_SPEC_PATH)
          end

          def create_stream(table, base_id, base_name)
            {
              name: "#{base_name}/#{SchemaHelper.clean_name(table["name"])}",
              action: "create",
              method: HTTP_POST,
              url: "#{AIRTABLE_URL_BASE}#{base_id}/#{table["id"]}",
              json_schema: SchemaHelper.get_json_schema(table),
              supported_sync_modes: %w[incremental],
              batch_support: true,
              batch_size: 10

            }.with_indifferent_access
          end

          def build_catalog_from_schema(schema, base_id, base_name)
            catalog = build_catalog(load_catalog)
            schema["tables"].each do |table|
              catalog.streams << build_stream(create_stream(table, base_id, base_name))
            end
            catalog
          end
        end
      end
    end
  end
end
