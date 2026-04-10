require "active_support"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/object/blank"
require "active_record"
require "active_job"

require_relative "rails_airtable_sync/version"
require_relative "rails_airtable_sync/errors"
require_relative "rails_airtable_sync/configuration"
require_relative "rails_airtable_sync/field_mapping"
require_relative "rails_airtable_sync/model_config"
require_relative "rails_airtable_sync/model"
require_relative "rails_airtable_sync/instrumentation"

# Type system
require_relative "rails_airtable_sync/type_system/base_type"
require_relative "rails_airtable_sync/type_system/types/string_type"
require_relative "rails_airtable_sync/type_system/types/integer_type"
require_relative "rails_airtable_sync/type_system/types/float_type"
require_relative "rails_airtable_sync/type_system/types/decimal_type"
require_relative "rails_airtable_sync/type_system/types/boolean_type"
require_relative "rails_airtable_sync/type_system/types/date_type"
require_relative "rails_airtable_sync/type_system/types/datetime_type"
require_relative "rails_airtable_sync/type_system/types/email_type"
require_relative "rails_airtable_sync/type_system/types/url_type"
require_relative "rails_airtable_sync/type_system/types/phone_type"
require_relative "rails_airtable_sync/type_system/types/single_select_type"
require_relative "rails_airtable_sync/type_system/types/multi_select_type"
require_relative "rails_airtable_sync/type_system/types/json_type"
require_relative "rails_airtable_sync/type_system/types/attachment_url_type"
require_relative "rails_airtable_sync/type_system/types/lookup_string_type"
require_relative "rails_airtable_sync/type_system/types/formula_safe_string_type"
require_relative "rails_airtable_sync/type_system/airtable_type_map"
require_relative "rails_airtable_sync/type_system/serializer"

# API
require_relative "rails_airtable_sync/api/response"
require_relative "rails_airtable_sync/api/client"

# Schema
require_relative "rails_airtable_sync/schema/inspector"
require_relative "rails_airtable_sync/schema/mutation_executor"
require_relative "rails_airtable_sync/schema/reconciler"

# Sync
require_relative "rails_airtable_sync/sync/checksum"
require_relative "rails_airtable_sync/sync/payload_builder"
require_relative "rails_airtable_sync/sync/record_resolver"
require_relative "rails_airtable_sync/sync/result"
require_relative "rails_airtable_sync/sync/engine"

# State
require_relative "rails_airtable_sync/state/sync_record"

# Retry
require_relative "rails_airtable_sync/retry/policy"

# Jobs
require_relative "rails_airtable_sync/jobs/sync_job"
require_relative "rails_airtable_sync/jobs/batch_sync_job"

# Rails integration
require_relative "rails_airtable_sync/railtie" if defined?(Rails::Railtie)

module RailsAirtableSync
  class << self
    # ─── Configuration ─────────────────────────────────────────────────────

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def configured?
      !configuration.api_key.nil?
    end

    def reset_configuration!
      @configuration  = nil
      @engine         = nil
      @instrumentation = nil
    end

    # ─── Model registry ────────────────────────────────────────────────────

    def registered_models
      @registered_models ||= []
    end

    def register_model(model_class)
      registered_models << model_class unless registered_models.include?(model_class)
    end

    # ─── Public sync API ───────────────────────────────────────────────────

    # Sync all records for a model, or a single record.
    #
    #   RailsAirtableSync.sync(Customer)
    #   RailsAirtableSync.sync(Customer, record: customer)
    #
    # @return [Array<Sync::Result>] or [Sync::Result] for single-record mode
    def sync(model_class, record: nil)
      if record
        engine.sync_record(record)
      else
        engine.sync_model(model_class)
      end
    end

    # Sync all registered models.
    def sync_all
      registered_models.flat_map { |m| engine.sync_model(m) }
    end

    # Enqueue an ActiveJob for a model/record sync (non-blocking).
    def enqueue_sync(model_class, record: nil)
      if record
        Jobs::SyncJob.perform_later(model_class.name, record.id)
      else
        Jobs::BatchSyncJob.perform_later(model_class.name)
      end
    end

    # ─── Shared engine / instrumentation ───────────────────────────────────

    def engine
      @engine ||= Sync::Engine.new(
        client:          api_client,
        config:          configuration,
        instrumentation: instrumentation
      )
    end

    def instrumentation
      @instrumentation ||= Instrumentation.new(configuration)
    end

    def api_client
      @api_client ||= Api::Client.new(configuration)
    end
  end
end
