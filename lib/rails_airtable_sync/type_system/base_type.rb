module RailsAirtableSync
  module TypeSystem
    # Abstract base class for all canonical type serializers.
    #
    # Subclasses must implement:
    #   #serialize(value, mapping:, config:)  → Airtable-safe value or nil
    #
    # They may also override #validate! for pre-serialization checks.
    class BaseType
      # @param value    [Object]        raw Rails value
      # @param mapping  [FieldMapping]
      # @param config   [Configuration]
      # @return         [Object, nil]   Airtable-safe value
      def serialize(value, mapping:, config:)
        raise NotImplementedError
      end

      protected

      def null_check!(value, mapping:)
        return unless value.nil?
        return if mapping.nullable?

        raise ValidationError.new(
          "Field '#{mapping.airtable_field}' is non-nullable but received nil",
          field_name:    mapping.airtable_field,
          raw_value:     nil,
          expected_type: self.class.name
        )
      end

      def strict?(config)
        config.strict_types
      end
    end
  end
end
