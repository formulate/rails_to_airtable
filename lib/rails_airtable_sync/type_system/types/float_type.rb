module RailsAirtableSync
  module TypeSystem
    module Types
      class FloatType < BaseType
        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          case value
          when Float   then value
          when Integer then value.to_f
          when String
            if strict?(config) && !mapping.coerce?
              raise ValidationError.new(
                "Field '#{mapping.airtable_field}' expects Float, got String",
                field_name: mapping.airtable_field, raw_value: value, expected_type: :float
              )
            end
            Float(value)
          else
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' cannot coerce #{value.class} to Float",
              field_name: mapping.airtable_field, raw_value: value, expected_type: :float
            )
          end
        end
      end
    end
  end
end
