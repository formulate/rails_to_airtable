module RailsAirtableSync
  module TypeSystem
    module Types
      class StringType < BaseType
        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          str = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

          if mapping.max_length && str.bytesize > mapping.max_length
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' exceeds max_length #{mapping.max_length}",
              field_name:    mapping.airtable_field,
              raw_value:     value,
              expected_type: :string
            )
          end

          str
        end
      end

      # :text is the same serialization as :string but maps to Airtable "long text"
      TextType = StringType
    end
  end
end
