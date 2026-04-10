require "digest"
require "json"

module RailsAirtableSync
  module Sync
    # Computes a deterministic SHA-256 checksum over a set of Rails attribute
    # values (post-serialisation) to detect whether a record has changed since
    # the last successful sync.
    module Checksum
      module_function

      # @param record        [ActiveRecord::Base]
      # @param model_config  [ModelConfig]
      # @param serializer    [TypeSystem::Serializer]
      # @return              [String] hex SHA-256 digest
      def compute(record, model_config:, serializer:)
        fields = model_config.checksum_fields.sort.map do |attr|
          mapping = model_config.mapping_for_attr(attr)
          raise ConfigurationError, "checksum_field :#{attr} has no field mapping in #{model_config.model_class}" unless mapping

          raw = record.public_send(attr)
          serialized = serializer.serialize_field(raw, mapping: mapping)
          serialized = nil if serialized == :omit

          [mapping.airtable_field, serialized]
        end

        canonical = JSON.generate(fields)
        Digest::SHA256.hexdigest(canonical)
      end
    end
  end
end
