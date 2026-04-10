require "uri"

module RailsAirtableSync
  module TypeSystem
    module Types
      class UrlType < BaseType
        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          str = value.to_s.strip
          uri = URI.parse(str)

          unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' expects an http(s) URL, got: #{str.inspect}",
              field_name: mapping.airtable_field, raw_value: value, expected_type: :url
            )
          end

          str
        rescue URI::InvalidURIError
          raise ValidationError.new(
            "Field '#{mapping.airtable_field}' has invalid URL: #{value.inspect}",
            field_name: mapping.airtable_field, raw_value: value, expected_type: :url
          )
        end
      end
    end
  end
end
