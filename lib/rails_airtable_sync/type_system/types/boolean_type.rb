module RailsAirtableSync
  module TypeSystem
    module Types
      class BooleanType < BaseType
        TRUTHY  = [true, 1, "true", "1", "t"].freeze
        FALSY   = [false, 0, "false", "0", "f"].freeze

        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          if TRUTHY.include?(value)
            true
          elsif FALSY.include?(value)
            false
          else
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' cannot coerce #{value.inspect} to Boolean. " \
              "Use true/false. Set coerce: true to enable string coercion.",
              field_name:    mapping.airtable_field,
              raw_value:     value,
              expected_type: :boolean
            )
          end
        end
      end
    end
  end
end
