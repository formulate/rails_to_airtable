module RailsAirtableSync
  module State
    # ActiveRecord model that tracks the sync state for each Rails record ↔
    # Airtable record pairing.
    #
    # Table: airtable_sync_records
    class SyncRecord < ActiveRecord::Base
      self.table_name = "airtable_sync_records"

      STATUSES = %w[pending synced failed skipped quarantined].freeze

      validates :syncable_type,  presence: true
      validates :syncable_id,    presence: true
      validates :airtable_table, presence: true
      validates :status,         inclusion: { in: STATUSES }

      scope :pending,     -> { where(status: "pending") }
      scope :failed,      -> { where(status: "failed") }
      scope :quarantined, -> { where(status: "quarantined") }
      scope :synced,      -> { where(status: "synced") }

      scope :for_model, ->(model_class) {
        where(syncable_type: model_class.name)
      }

      scope :for_table, ->(table_name) {
        where(airtable_table: table_name)
      }

      # Mark a record as quarantined, preventing future automatic retries.
      def quarantine!(error_class: nil, error_message: nil)
        update!(
          status:             "quarantined",
          last_error_class:   error_class,
          last_error_message: error_message,
          last_attempted_at:  Time.current
        )
      end

      # Mark as failed and increment failure counter.
      def record_failure!(error)
        update!(
          status:             "failed",
          failure_count:      failure_count.to_i + 1,
          last_error_class:   error.class.name,
          last_error_message: error.message,
          last_attempted_at:  Time.current
        )
      end

      def exceeded_failure_threshold?(threshold = 5)
        failure_count.to_i >= threshold
      end
    end
  end
end
