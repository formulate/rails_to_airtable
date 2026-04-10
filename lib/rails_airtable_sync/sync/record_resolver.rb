module RailsAirtableSync
  module Sync
    # Resolves whether to create or update an Airtable record for a given Rails
    # record.  Uses the local sync state as the primary source of truth, with
    # a live Airtable lookup as a fallback to prevent duplicates.
    class RecordResolver
      def initialize(client:, config:)
        @client = client
        @config = config
      end

      # @param record        [ActiveRecord::Base]
      # @param model_config  [ModelConfig]
      # @param sync_record   [State::SyncRecord, nil] existing local sync state
      # @return              [:create, :update, String] – operation and Airtable record ID (or nil for :create)
      def resolve(record, model_config:, sync_record:)
        # 1. Use cached local mapping if present
        if sync_record&.airtable_record_id.present?
          return [:update, sync_record.airtable_record_id]
        end

        # 2. Fall back to Airtable lookup by external ID to prevent duplicates
        external_mapping = model_config.external_id_mapping
        return [:create, nil] unless external_mapping

        external_value = record.public_send(external_mapping.from)
        remote_records = lookup_by_external_id(
          model_config.table_name,
          external_mapping.airtable_field,
          external_value
        )

        case remote_records.size
        when 0
          [:create, nil]
        when 1
          [:update, remote_records.first["id"]]
        else
          raise ConsistencyError,
                "Found #{remote_records.size} Airtable records with " \
                "#{external_mapping.airtable_field} = #{external_value.inspect} in " \
                "table '#{model_config.table_name}'. Manual intervention required."
        end
      end

      private

      def lookup_by_external_id(table_name, field_name, value)
        # Build a safe Airtable formula: {Field Name} = "value" or {Field Name} = number
        formula = if value.is_a?(Numeric)
          "{#{field_name}} = #{value}"
        else
          "{#{field_name}} = \"#{value.to_s.gsub('"', '\\"')}\""
        end

        @client.list_records(table_name, filter_formula: formula, page_size: 5)
      rescue TransportError, ApiError
        # If lookup fails, safer to return empty and attempt a create which will
        # fail visibly on duplicate unique constraint rather than silently skip.
        []
      end
    end
  end
end
