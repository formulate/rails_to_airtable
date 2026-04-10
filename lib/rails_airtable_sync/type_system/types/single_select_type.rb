module RailsAirtableSync
  module TypeSystem
    module Types
      class SingleSelectType < BaseType
        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          str = value.to_s

          if mapping.allowed_values && !mapping.allowed_values.include?(str)
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' received unknown single_select value " \
              "#{str.inspect}. Allowed: #{mapping.allowed_values.inspect}",
              field_name:    mapping.airtable_field,
              raw_value:     value,
              expected_type: :single_select
            )
          end

          str
        end
      end
    end
  end
end
