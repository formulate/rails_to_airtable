module RailsAirtableSync
  module TypeSystem
    module Types
      # Serializes a string with characters that could break Airtable formula
      # fields escaped or stripped, suitable for use as a formula argument.
      class FormulaSafeStringType < BaseType
        UNSAFE_CHARS = /["'\\]/.freeze

        def serialize(value, mapping:, config:)
          null_check!(value, mapping: mapping)
          return nil if value.nil?

          value
            .to_s
            .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
            .gsub(UNSAFE_CHARS, "")
        end
      end
    end
  end
end
