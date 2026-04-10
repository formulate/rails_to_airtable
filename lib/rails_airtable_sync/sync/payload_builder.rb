module RailsAirtableSync
  module Sync
    # Builds the Airtable fields hash for a Rails record, applying type
    # serialisation and omitting nil fields configured with omit_on_nil.
    class PayloadBuilder
      def initialize(serializer:)
        @serializer = serializer
      end

      # @param record       [ActiveRecord::Base]
      # @param model_config [ModelConfig]
      # @return             [Hash] Airtable-ready fields hash
      def build(record, model_config:)
        fields = {}

        model_config.field_mappings.each do |mapping|
          raw   = record.public_send(mapping.from)
          value = @serializer.serialize_field(raw, mapping: mapping)
          next if value == :omit

          fields[mapping.airtable_field] = value
        end

        fields
      end
    end
  end
end
