module RailsAirtableSync
  module TypeSystem
    module Types
      class PhoneType < BaseType
        # Minimal: must contain digits; allow +, spaces, dashes, parens
        PATTERN = /\A[\d\s\+\-\(\)\.]{7,20}\z/

        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          str = value.to_s.strip

          unless PATTERN.match?(str)
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' has invalid phone number: #{str.inspect}",
              field_name: mapping.airtable_field, raw_value: value, expected_type: :phone
            )
          end

          str
        end
      end
    end
  end
end
