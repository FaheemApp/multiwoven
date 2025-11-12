# frozen_string_literal: true

require "json"

module ReverseEtl
  module Transformers
    class UserMapping < Base
      BOOLEAN_LITERALS = { "true" => true, "false" => false }.freeze
      NUMERIC_REGEX = /\A[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?\z/.freeze

      attr_accessor :mappings, :record, :destination_data

      def transform(sync, sync_record)
        @mappings = sync.configuration
        @record = sync_record.record
        @destination_data = {}

        if mappings.is_a?(Array)
          transform_record_v2
        else
          transform_record_v1
        end

        @destination_data
      rescue StandardError => e
        # Utils::ExceptionReporter.report(e, {
        #                                   sync_id: sync.id,
        #                                   sync_record_id: sync_record.id
        #                                 })
        Rails.logger.error({
          error_message: e.message,
          sync_id: sync.id,
          stack_trace: Rails.backtrace_cleaner.clean(e.backtrace)
        }.to_s)
      end

      private

      def transform_record_v1
        mappings.each do |source_key, dest_path|
          dest_keys = dest_path.split(".")
          mapped_destination_value = record[source_key]
          extract_destination_mapping(dest_keys, mapped_destination_value)
        end
      end

      def transform_record_v2
        mappings.each do |mapping|
          mapping = mapping.with_indifferent_access
          case mapping[:mapping_type]
          when "standard"
            standard_mapping(mapping)
          when "static"
            static_mapping(mapping)
          when "template"
            template_mapping(mapping)
          when "vector"
            vector_mapping(mapping)
          end
        end
      end

      def vector_mapping(mapping)
        dest_keys = mapping[:to].split(".")
        source_key = mapping[:from]
        embedding_config = mapping[:embedding_config]
        mapped_destination_value = if embedding_config
                                     ReverseEtl::Transformers::Embeddings::EmbeddingService
                                       .new(embedding_config:).generate_embedding(record[source_key])
                                   else
                                     record[source_key]
                                   end

        extract_destination_mapping(dest_keys, mapped_destination_value)
      end

      def standard_mapping(mapping)
        dest_keys = mapping[:to].split(".")
        source_key = mapping[:from]

        mapped_destination_value = record[source_key]

        sanitized_mapped_value = if mapped_destination_value.is_a?(String)
                                   mapped_destination_value.gsub("'", "''")
                                 else
                                   mapped_destination_value
                                 end

        extract_destination_mapping(dest_keys, sanitized_mapped_value)
      end

      def static_mapping(mapping)
        dest_keys = mapping[:to].split(".")
        static_value = mapping[:from]
        extract_destination_mapping(dest_keys, static_value)
      end

      def template_mapping(mapping)
        dest_keys = mapping[:to].split(".")
        template = mapping[:from]
        Liquid::Template.register_filter(Liquid::CustomFilters)
        liquid_template = Liquid::Template.parse(template)
        rendered_text = liquid_template.render(record)

        interpreted_value = normalize_template_output(rendered_text)
        extract_destination_mapping(dest_keys, interpreted_value)
      end

      def normalize_template_output(value)
        return value unless value.is_a?(String)

        stripped_value = value.strip
        return value if stripped_value.empty?

        json_value = parse_json_container(stripped_value)
        return json_value unless json_value.nil?

        quoted_value = parse_quoted_json_string(stripped_value)
        return quoted_value unless quoted_value.nil?

        boolean_literal = parse_boolean_literal(stripped_value)
        return boolean_literal unless boolean_literal.nil?

        return nil if null_literal?(stripped_value)

        numeric_literal = parse_numeric_literal(stripped_value)
        return numeric_literal unless numeric_literal.nil?

        value
      end

      def parse_json_container(value)
        return unless value.start_with?("{", "[")

        JSON.parse(value)
      rescue JSON::ParserError
        nil
      end

      def parse_quoted_json_string(value)
        return unless value.start_with?('"') && value.end_with?('"')

        JSON.parse(value)
      rescue JSON::ParserError
        nil
      end

      def parse_boolean_literal(value)
        BOOLEAN_LITERALS[value.downcase]
      end

      def null_literal?(value)
        value.casecmp?("null")
      end

      def parse_numeric_literal(value)
        return unless value.match?(NUMERIC_REGEX)

        value.match?(/[eE.]/) ? value.to_f : value.to_i
      end

      def extract_destination_mapping(dest_keys, mapped_destination_value)
        current = destination_data

        dest_keys.each_with_index do |key, index|
          is_last_key = index == dest_keys.length - 1
          is_array_key = key.include?("[]")

          if is_last_key
            # Handle array notation in the path
            set_value(current, key, mapped_destination_value, is_array_key)
          elsif is_array_key
            array_key = key.gsub("[]", "")
            current[array_key] ||= []
            # Use the last element of the array or create a new one if empty
            current = current[array_key].last || current[array_key].push({}).last
          else
            current[key] ||= {}
            current = current[key]
          end
        end
      end

      def set_value(current, key, value, is_array)
        if is_array
          array_key = key.gsub("[]", "")
          current[array_key] ||= []
          current[array_key] << value
        else
          current[key] = value
        end
      end
    end
  end
end
