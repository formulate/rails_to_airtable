require "time"

module RailsAirtableSync
  module TypeSystem
    module Types
      class DatetimeType < BaseType
        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          case value
          when Time, DateTime
            value.utc.iso8601
          when Date
            # Treat as midnight UTC
            value.to_time.utc.iso8601
          when String
            Time.parse(value).utc.iso8601
          else
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' cannot serialize #{value.class} as Datetime",
              field_name: mapping.airtable_field, raw_value: value, expected_type: :datetime
            )
          end
        rescue ArgumentError, TypeError => e
          raise ValidationError.new(
            "Field '#{mapping.airtable_field}' datetime parse error: #{e.message}",
            field_name: mapping.airtable_field, raw_value: value, expected_type: :datetime
          )
        end
      end
    end
  end
end
