# frozen_string_literal: true

module Models
  # Fetches and stores schema information for a model by running a lightweight query.
  class SchemaCacheService
    TYPE_MAP = {
      Integer => "integer",
      Float => "number",
      BigDecimal => "number",
      TrueClass => "boolean",
      FalseClass => "boolean",
      Date => "datetime",
      Time => "datetime",
      DateTime => "datetime"
    }.freeze

    def initialize(model)
      @model = model
    end

    def call(force: false)
      return {} unless should_cache_schema?(force)

      schema_data = extract_schema_from_source
      return {} if schema_data.blank?

      persist_schema(schema_data)
      schema_data
    rescue StandardError => e
      Rails.logger.error("Failed to cache schema for model #{@model.id}: #{e.message}")
      {}
    end

    private

    def should_cache_schema?(force)
      return false unless @model.requires_query?
      return false if @model.query.blank?
      return true if force

      @model.schema.blank?
    end

    def extract_schema_from_source
      result = Array(@model.connector.execute_query(@model.query, limit: 1))
      return {} if result.empty?

      row = first_hash_row(result)
      return {} if row.blank?

      normalized_row = row.transform_keys(&:to_s)
      normalized_row.transform_values { |value| infer_type(value) }
    end

    def first_hash_row(result)
      result.each do |row|
        return row if row.is_a?(Hash)

        row_hash = extract_row_data(row)
        return row_hash if row_hash.present?
      end

      {}
    end

    def extract_row_data(row)
      if row.respond_to?(:record) && row.record.respond_to?(:data)
        row.record.data
      elsif row.respond_to?(:data)
        row.data
      elsif row.respond_to?(:to_h)
        row.to_h
      elsif row.is_a?(Struct)
        row.to_h
      elsif row.respond_to?(:[])
        row[:data] || row["data"]
      end
    end

    def persist_schema(schema_data)
      @model.update_column(:schema, schema_data)
    end

    def infer_type(value)
      TYPE_MAP.each do |klass, type|
        return type if value.is_a?(klass)
      end

      value.nil? ? "unknown" : "string"
    end
  end
end
