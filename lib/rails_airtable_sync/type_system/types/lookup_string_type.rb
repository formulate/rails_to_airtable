module RailsAirtableSync
  module TypeSystem
    module Types
      # Serializes a value meant to be used in Airtable lookup/linked fields
      # as a plain string representation.
      class LookupStringType < BaseType
        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        end
      end
    end
  end
end
