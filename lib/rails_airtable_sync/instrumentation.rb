require "active_support/notifications"

module RailsAirtableSync
  # Thin wrapper that fires ActiveSupport::Notifications events and writes
  # structured log lines simultaneously.
  #
  # All public sync/schema operations call #emit with an event name and a hash
  # of attributes.  Consumers can subscribe via:
  #
  #   ActiveSupport::Notifications.subscribe("airtable_sync.sync_succeeded") do |*args|
  #     event = ActiveSupport::Notifications::Event.new(*args)
  #     # event.payload contains the attribute hash
  #   end
  class Instrumentation
    # Events emitted by the gem
    EVENTS = %w[
      airtable_sync.sync_started
      airtable_sync.sync_succeeded
      airtable_sync.sync_failed
      airtable_sync.record_skipped
      airtable_sync.schema_drift_detected
      airtable_sync.schema_inspection_started
      airtable_sync.schema_reconciled
      airtable_sync.schema_change_applied
      airtable_sync.schema_conflict_detected
      airtable_sync.schema_change_blocked
    ].freeze

    def initialize(config)
      @config  = config
      @logger  = config.logger
      @metrics = Hash.new(0)   # in-process counters (exportable by consumers)
    end

    # Emit an ActiveSupport::Notifications event and write a structured log line.
    # @param event_name [String]
    # @param payload    [Hash]
    def emit(event_name, **payload)
      redacted = redact(payload)

      ActiveSupport::Notifications.instrument(event_name, redacted)

      log_level = log_level_for(event_name)
      @logger.public_send(log_level, format_log(event_name, redacted))

      increment_metric(event_name, redacted)
    rescue StandardError => e
      # Instrumentation must never crash the sync
      @logger.error("[RailsAirtableSync] Instrumentation error: #{e.message}")
    end

    # Return a snapshot of in-process metric counters.
    def metrics_snapshot
      @metrics.dup
    end

    private

    def format_log(event_name, payload)
      pairs = payload.map { |k, v| "#{k}=#{v.inspect}" }.join(" ")
      "[RailsAirtableSync] event=#{event_name} #{pairs}"
    end

    def log_level_for(event_name)
      case event_name
      when "airtable_sync.sync_failed",
           "airtable_sync.schema_conflict_detected",
           "airtable_sync.schema_change_blocked"
        :warn
      else
        :info
      end
    end

    def increment_metric(event_name, payload)
      case event_name
      when "airtable_sync.sync_succeeded"
        op = payload[:operation]
        @metrics["records_synced_total"] += 1 if op && op != :skip
        @metrics["records_skipped_total"] += 1 if op == :skip
      when "airtable_sync.sync_failed"
        @metrics["records_failed_total"] += 1
      when "airtable_sync.record_skipped"
        @metrics["records_skipped_total"] += 1
      when "airtable_sync.schema_change_applied"
        case payload[:action]
        when :create_table then @metrics["schema_tables_created_total"] += 1
        when :create_field then @metrics["schema_fields_created_total"] += 1
        when :update_field then @metrics["schema_fields_updated_total"] += 1
        end
      when "airtable_sync.schema_conflict_detected"
        @metrics["schema_conflicts_total"] += 1
      when "airtable_sync.schema_change_blocked"
        @metrics["schema_changes_blocked_total"] += 1
      end
    end

    def redact(payload)
      return payload unless @config.sensitive_fields.any?

      payload.transform_values.with_index do |value, idx|
        key = payload.keys[idx]
        @config.redacted?(key) ? "[REDACTED]" : value
      end
    end
  end
end
