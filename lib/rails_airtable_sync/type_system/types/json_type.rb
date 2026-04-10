require "json"

module RailsAirtableSync
  module TypeSystem
    module Types
      class JsonType < BaseType
        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          case value
          when String
            # Validate it is already valid JSON
            JSON.parse(value)
            value
          else
            JSON.generate(value)
          end
        rescue JSON::GeneratorError, JSON::ParserError => e
          raise SerializationError.new(
            "Field '#{mapping.airtable_field}' JSON serialization failed: #{e.message}",
            field_name: mapping.airtable_field, raw_value: value, expected_type: :json
          )
        end
      end
    end
  end
end
