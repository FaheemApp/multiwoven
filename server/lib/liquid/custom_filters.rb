# frozen_string_literal: true

module Liquid
  module CustomFilters
    CAST_METHODS = {
      "string" => :to_s,
      "number" => :to_f,
      "boolean" => ->(input) { ActiveRecord::Type::Boolean.new.cast(input) }
    }.freeze

    def cast(input, type)
      method = CAST_METHODS[type]
      method ? apply_cast_method(input, method) : input
    end

    # Parse a JSON string into Ruby object (array or hash)
    # Returns the original input if JSON parsing fails
    def parse_json(input)
      return input if input.blank?
      return input unless input.is_a?(String)

      JSON.parse(input)
    rescue JSON::ParserError
      input
    end

    # Convert input to JSON array string
    # Handles various input types: arrays, strings, comma-separated values
    # Returns a JSON string that will be parsed by normalize_template_output
    def to_json_array(input, delimiter = ",")
      return "[]" if input.blank?
      return input.to_json if input.is_a?(Array)

      # If it's a JSON string, return it as-is
      if input.is_a?(String) && (input.strip.start_with?("[") || input.strip.start_with?("{"))
        begin
          parsed = JSON.parse(input)
          return parsed.to_json if parsed.is_a?(Array)
          return [parsed].to_json if parsed.is_a?(Hash)
        rescue JSON::ParserError
          # Continue with other parsing methods
        end
      end

      # Split by delimiter if it's a string and return as JSON
      if input.is_a?(String)
        input.split(delimiter).map(&:strip).reject(&:blank?).to_json
      else
        [input].to_json
      end
    end

    def regex_replace(input, pattern, replacement = "", flags = "")
      re = build_regexp(pattern, flags)
      input.gsub(re, replacement)
    end

    def match_regex(input, pattern, flags = "")
      re = build_regexp(pattern, flags)
      if re.match?(input)
        input
      else
        Raise StandardError, "Input does not match regex pattern"
      end
    end

    def to_datetime(input, existing_date_format)
      return input if input.blank?

      DateTime.strptime(input, existing_date_format)&.iso8601
    end

    private

    def apply_cast_method(input, method)
      method.is_a?(Proc) ? method.call(input) : input.send(method)
    end

    def build_regexp(pattern, flags)
      options = flags.chars.reduce(0) do |opts, flag|
        opts | flag_option(flag)
      end
      Regexp.new(pattern, options)
    end

    # Maps single character flags to their corresponding Regexp option constants.
    # Note: Ruby does not support 'n', 'e', 's', 'u' flags directly, and 'o' flag behavior is implicit.
    #       We handle common flags here and use FIXEDENCODING for unsupported flags as a placeholder.
    def flag_option(flag)
      case flag
      when "i" then Regexp::IGNORECASE
      when "m" then Regexp::MULTILINE
      when "x" then Regexp::EXTENDED
      when "n", "e", "s", "u" then Regexp::FIXEDENCODING
      else 0 # No action for unrecognized flags
      end
    end
  end
end
