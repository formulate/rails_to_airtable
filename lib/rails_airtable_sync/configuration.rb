require "logger"

module RailsAirtableSync
  class Configuration
    # ─── Airtable credentials ────────────────────────────────────────────────
    attr_accessor :api_key
    attr_accessor :base_id

    # ─── HTTP timeouts (seconds) ─────────────────────────────────────────────
    attr_accessor :timeout       # read/write timeout
    attr_accessor :open_timeout  # connection timeout

    # ─── Retry policy ────────────────────────────────────────────────────────
    # :exponential | :linear | :constant
    attr_accessor :max_retries
    attr_accessor :retry_backoff
    attr_accessor :retry_jitter

    # ─── Error behaviour ─────────────────────────────────────────────────────
    # When true, any single-record failure aborts the entire sync run.
    attr_accessor :fail_fast
    # :mark_failed | :raise | :skip
    attr_accessor :on_validation_error
    # :quarantine | :raise | :skip
    attr_accessor :on_consistency_error

    # ─── Delete policy ───────────────────────────────────────────────────────
    attr_accessor :enable_deletes
    # :none | :clear_fields | :archive_flag | :delete_record
    attr_accessor :delete_strategy

    # ─── Type strictness ─────────────────────────────────────────────────────
    attr_accessor :strict_types

    # ─── Integrity ───────────────────────────────────────────────────────────
    # Re-read the Airtable record after every write and compare to payload.
    attr_accessor :verify_after_write
    # Validate that the remote Airtable schema matches mappings before sync.
    attr_accessor :validate_remote_schema

    # ─── State persistence ───────────────────────────────────────────────────
    attr_accessor :persist_sync_state
    attr_accessor :use_advisory_locks

    # ─── Schema management ───────────────────────────────────────────────────
    attr_accessor :auto_manage_schema
    attr_accessor :auto_create_tables
    attr_accessor :auto_create_fields
    attr_accessor :auto_update_fields
    attr_accessor :allow_destructive_schema_changes
    # :fail | :ignore | :replace | :archive_and_replace
    attr_accessor :schema_conflict_policy

    # ─── Observability ───────────────────────────────────────────────────────
    attr_accessor :logger

    # ─── Batch/backpressure ──────────────────────────────────────────────────
    attr_accessor :batch_size
    # Seconds to sleep between batches (nil = no sleep)
    attr_accessor :batch_sleep

    # ─── PII / sensitive field redaction ────────────────────────────────────
    # Array of field names whose values are redacted in logs.
    attr_accessor :sensitive_fields

    VALID_RETRY_BACKOFFS        = %i[exponential linear constant].freeze
    VALID_DELETE_STRATEGIES     = %i[none clear_fields archive_flag delete_record].freeze
    VALID_SCHEMA_CONFLICT_POLICIES = %i[fail ignore replace archive_and_replace].freeze
    VALID_VALIDATION_ERROR_ACTIONS = %i[mark_failed raise skip].freeze
    VALID_CONSISTENCY_ERROR_ACTIONS = %i[quarantine raise skip].freeze

    def initialize
      # Credentials — must be set explicitly.
      @api_key    = nil
      @base_id    = nil

      # HTTP
      @timeout      = 10
      @open_timeout = 3

      # Retry
      @max_retries   = 3
      @retry_backoff = :exponential
      @retry_jitter  = true

      # Error behaviour
      @fail_fast              = false
      @on_validation_error    = :mark_failed
      @on_consistency_error   = :quarantine

      # Deletes — off by default
      @enable_deletes   = false
      @delete_strategy  = :archive_flag

      # Types
      @strict_types = true

      # Integrity
      @verify_after_write     = true
      @validate_remote_schema = true

      # State
      @persist_sync_state  = true
      @use_advisory_locks  = true

      # Schema management — on by default, destructive off
      @auto_manage_schema                = true
      @auto_create_tables                = true
      @auto_create_fields                = true
      @auto_update_fields                = true
      @allow_destructive_schema_changes  = false
      @schema_conflict_policy            = :fail

      # Observability
      @logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)

      # Batch
      @batch_size  = 100
      @batch_sleep = nil

      # PII
      @sensitive_fields = []
    end

    def validate!
      raise ConfigurationError, "api_key must be set" if api_key.nil? || api_key.empty?
      raise ConfigurationError, "base_id must be set" if base_id.nil? || base_id.empty?

      unless VALID_RETRY_BACKOFFS.include?(retry_backoff)
        raise ConfigurationError, "retry_backoff must be one of #{VALID_RETRY_BACKOFFS}"
      end

      unless VALID_DELETE_STRATEGIES.include?(delete_strategy)
        raise ConfigurationError, "delete_strategy must be one of #{VALID_DELETE_STRATEGIES}"
      end

      unless VALID_SCHEMA_CONFLICT_POLICIES.include?(schema_conflict_policy)
        raise ConfigurationError,
              "schema_conflict_policy must be one of #{VALID_SCHEMA_CONFLICT_POLICIES}"
      end

      unless VALID_VALIDATION_ERROR_ACTIONS.include?(on_validation_error)
        raise ConfigurationError,
              "on_validation_error must be one of #{VALID_VALIDATION_ERROR_ACTIONS}"
      end

      unless VALID_CONSISTENCY_ERROR_ACTIONS.include?(on_consistency_error)
        raise ConfigurationError,
              "on_consistency_error must be one of #{VALID_CONSISTENCY_ERROR_ACTIONS}"
      end

      self
    end

    def redacted?(field_name)
      sensitive_fields.map(&:to_s).include?(field_name.to_s)
    end
  end
end
