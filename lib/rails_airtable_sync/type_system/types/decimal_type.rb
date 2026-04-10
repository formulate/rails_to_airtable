require "bigdecimal"

module RailsAirtableSync
  module TypeSystem
    module Types
      class DecimalType < BaseType
        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          dec = to_decimal(value, mapping: mapping, config: config)
          # Airtable accepts JSON numbers; send as float to avoid precision surprises
          dec.to_f
        end

        private

        def to_decimal(value, mapping:, config:)
          case value
          when BigDecimal then value
          when Integer    then BigDecimal(value.to_s)
          when Float      then BigDecimal(value.to_s)
          when String
            if strict?(config) && !mapping.coerce?
              raise ValidationError.new(
                "Field '#{mapping.airtable_field}' expects Decimal, got String",
                field_name: mapping.airtable_field, raw_value: value, expected_type: :decimal
              )
            end
            BigDecimal(value)
          else
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' cannot coerce #{value.class} to Decimal",
              field_name: mapping.airtable_field, raw_value: value, expected_type: :decimal
            )
          end
        rescue ArgumentError => e
          raise ValidationError.new(
            "Field '#{mapping.airtable_field}' decimal parse error: #{e.message}",
            field_name: mapping.airtable_field, raw_value: value, expected_type: :decimal
          )
        end
      end
    end
  end
end
