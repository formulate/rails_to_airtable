module RailsAirtableSync
  module TypeSystem
    module Types
      class EmailType < BaseType
        # Minimal RFC-5322 check: something@something.something
        PATTERN = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          str = value.to_s.strip

          unless PATTERN.match?(str)
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' has invalid email: #{str.inspect}",
              field_name:    mapping.airtable_field,
              raw_value:     value,
              expected_type: :email
            )
          end

          str
        end
      end
    end
  end
end
