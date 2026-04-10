module RailsAirtableSync
  module Jobs
    # ActiveJob job that syncs a single Rails model record to Airtable.
    #
    # Usage (automatic via after_commit):
    #   airtable_sync on: :commit
    #
    # Usage (manual):
    #   RailsAirtableSync::Jobs::SyncJob.perform_later("Customer", 42)
    class SyncJob < ActiveJob::Base
      queue_as :default

      # @param model_name [String]  e.g. "Customer"
      # @param record_id  [Integer] primary key of the record to sync
      def perform(model_name, record_id)
        model_class  = model_name.constantize
        record       = model_class.find(record_id)

        RailsAirtableSync.sync(model_class, record: record)
      rescue ActiveRecord::RecordNotFound
        # Record was deleted before the job ran — nothing to sync.
        logger.info "[RailsAirtableSync] #{model_name}##{record_id} not found, skipping sync."
      end
    end
  end
end
