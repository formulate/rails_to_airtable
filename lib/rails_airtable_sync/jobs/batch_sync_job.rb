module RailsAirtableSync
  module Jobs
    # ActiveJob job that performs a full (or failed-only) sync for one model.
    #
    # Usage:
    #   RailsAirtableSync::Jobs::BatchSyncJob.perform_later("Customer")
    #   RailsAirtableSync::Jobs::BatchSyncJob.perform_later("Customer", only_failed: true)
    class BatchSyncJob < ActiveJob::Base
      queue_as :default

      # @param model_name   [String]  e.g. "Customer"
      # @param only_failed  [Boolean] when true, re-sync only failed/pending records
      def perform(model_name, only_failed: false)
        model_class = model_name.constantize
        engine      = RailsAirtableSync.engine

        results = engine.sync_model(model_class, only_failed: only_failed)

        failed  = results.count(&:failed?)
        skipped = results.count(&:skipped?)
        synced  = results.count(&:success?) - skipped

        logger.info "[RailsAirtableSync] BatchSyncJob #{model_name} complete. " \
                    "synced=#{synced} skipped=#{skipped} failed=#{failed}"
      end
    end
  end
end
