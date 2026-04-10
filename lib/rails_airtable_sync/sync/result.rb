module RailsAirtableSync
  module Sync
    # Value object describing the outcome of syncing one record.
    Result = Struct.new(
      :model_class,
      :record_id,
      :airtable_table,
      :operation,        # :create | :update | :skip | :delete | :failed | :quarantined
      :checksum_changed, # bool
      :duration_ms,      # Integer
      :airtable_record_id,
      :error,            # Exception or nil
      :validation_errors, # Array<Hash> field-level errors
      keyword_init: true
    ) do
      def success? = %i[create update skip delete].include?(operation)
      def failed?  = operation == :failed
      def skipped? = operation == :skip
    end
  end
end
