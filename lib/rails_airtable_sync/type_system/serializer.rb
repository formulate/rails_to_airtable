module RailsAirtableSync
  module TypeSystem
    # Coordinates type serialization for a complete record payload.
    class Serializer
      TYPE_REGISTRY = {
        string:              -> { Types::StringType.new },
        text:                -> { Types::TextType.new },
        integer:             -> { Types::IntegerType.new },
        float:               -> { Types::FloatType.new },
        decimal:             -> { Types::DecimalType.new },
        boolean:             -> { Types::BooleanType.new },
        date:                -> { Types::DateType.new },
        datetime:            -> { Types::DatetimeType.new },
        email:               -> { Types::EmailType.new },
        url:                 -> { Types::UrlType.new },
        phone:               -> { Types::PhoneType.new },
        single_select:       -> { Types::SingleSelectType.new },
        multi_select:        -> { Types::MultiSelectType.new },
        json:                -> { Types::JsonType.new },
        attachment_url:      -> { Types::AttachmentUrlType.new },
        lookup_string:       -> { Types::LookupStringType.new },
        formula_safe_string: -> { Types::FormulaSafeStringType.new }
      }.freeze

      def initialize(config)
        @config = config
      end

      # Serialize a single field value.
      #
      # @param value   [Object]        raw Rails value
      # @param mapping [FieldMapping]
      # @return        [Object, nil]   Airtable-safe representation
      def serialize_field(value, mapping:)
        serializer = type_serializer(mapping.type)

        resolved_value = resolve_value(value, mapping: mapping)

        # Handle nil with omit_on_nil / default
        if resolved_value.nil? && mapping.omit_on_nil
          return :omit
        end

        serializer.serialize(resolved_value, mapping: mapping, config: @config)
      end

      private

      def resolve_value(value, mapping:)
        if value.nil? && !mapping.default.nil?
          mapping.default
        else
          value
        end
      end

      def type_serializer(type)
        factory = TYPE_REGISTRY.fetch(type.to_sym) do
          raise ConfigurationError, "No serializer registered for type :#{type}"
        end
        factory.call
      end
    end
  end
end
