require "uri"

module RailsAirtableSync
  module TypeSystem
    module Types
      # Serializes to the Airtable attachment array format: [{url: "..."}]
      # Only absolute http(s) URLs are supported.
      class AttachmentUrlType < BaseType
        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          urls = Array(value).map(&:to_s).map(&:strip)

          urls.each do |url|
            uri = URI.parse(url)
            unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
              raise ValidationError.new(
                "Field '#{mapping.airtable_field}' attachment URL must be absolute http(s): #{url.inspect}",
                field_name:    mapping.airtable_field,
                raw_value:     value,
                expected_type: :attachment_url
              )
            end
          rescue URI::InvalidURIError
            raise ValidationError.new(
              "Field '#{mapping.airtable_field}' has invalid attachment URL: #{url.inspect}",
              field_name:    mapping.airtable_field,
              raw_value:     value,
              expected_type: :attachment_url
            )
          end

          urls.map { |url| { "url" => url } }
        end
      end
    end
  end
end
