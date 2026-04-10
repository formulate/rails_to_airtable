module RailsAirtableSync
  module TypeSystem
    module Types
      class IntegerType < BaseType
        MAX = (2**53 - 1)   # JavaScript safe integer (Airtable uses JSON numbers)
        MIN = -(2**53 - 1)

        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          int = coerce_integer(value, mapping: mapping, config: config)

          if int < MIN || int > MAX
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' integer #{int} is outside safe range",
              field_name:    mapping.airtable_field,
              raw_value:     value,
              expected_type: :integer
            )
          end

          int
        end

        private

        def coerce_integer(value, mapping:, config:)
          case value
          when Integer then value
          when String
            if strict?(config) && !mapping.coerce?
              raise ValidationError.new(
                "Field '#{mapping.airtable_field}' expects Integer, got String '#{value}'",
                field_name:    mapping.airtable_field,
                raw_value:     value,
                expected_type: :integer
              )
            end
            Integer(value)
          when Float
            if strict?(config) && !mapping.coerce?
              raise ValidationError.new(
                "Field '#{mapping.airtable_field}' expects Integer, got Float (#{value}). " \
                "Set coerce: true to allow.",
                field_name:    mapping.airtable_field,
                raw_value:     value,
                expected_type: :integer
              )
            end
            value.to_i
          else
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' cannot coerce #{value.class} to Integer",
              field_name:    mapping.airtable_field,
              raw_value:     value,
              expected_type: :integer
            )
          end
        end
      end
    end
  end
end
