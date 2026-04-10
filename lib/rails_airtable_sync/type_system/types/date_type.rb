require "date"

module RailsAirtableSync
  module TypeSystem
    module Types
      class DateType < BaseType
        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          case value
          when Date   then value.strftime("%Y-%m-%d")
          when Time, DateTime
            # Normalize to UTC first, then truncate to date
            value.utc.strftime("%Y-%m-%d")
          when String
            # Attempt ISO8601 parse
            Date.parse(value).strftime("%Y-%m-%d")
          else
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' cannot serialize #{value.class} as Date",
              field_name: mapping.airtable_field, raw_value: value, expected_type: :date
            )
          end
        rescue ArgumentError, TypeError => e
          raise ValidationError.new(
            "Field '#{mapping.airtable_field}' date parse error: #{e.message}",
            field_name: mapping.airtable_field, raw_value: value, expected_type: :date
          )
        end
      end
    end
  end
end
