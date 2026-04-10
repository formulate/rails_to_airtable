module RailsAirtableSync
  module TypeSystem
    module Types
      class MultiSelectType < BaseType
        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          values = Array(value).map(&:to_s).uniq

          if mapping.allowed_values
            unknown = values - mapping.allowed_values
            unless unknown.empty?
              raise ValidationError.new(
                "Field '#{mapping.airtable_field}' received unknown multi_select value(s) " \
                "#{unknown.inspect}. Allowed: #{mapping.allowed_values.inspect}",
                field_name:    mapping.airtable_field,
                raw_value:     value,
                expected_type: :multi_select
              )
            end
          end

          values
        end
      end
    end
  end
end
