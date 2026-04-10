module RailsAirtableSync
  module Sync
    # Orchestrates the complete sync workflow for a Rails model or single record.
    #
    # Workflow per record:
    #   1. Integrity pre-checks
    #   2. Build payload (serialise fields)
    #   3. Compute checksum
    #   4. Compare to last synced checksum → skip if unchanged
    #   5. Resolve Airtable record identity (create vs update)
    #   6. Write to Airtable
    #   7. Optionally verify response
    #   8. Persist sync state
    #   9. Emit instrumentation
    class Engine
      def initialize(client:, config:, instrumentation:)
        @client          = client
        @config          = config
        @instrumentation = instrumentation
        @serializer      = TypeSystem::Serializer.new(config)
        @payload_builder = PayloadBuilder.new(serializer: @serializer)
        @resolver        = RecordResolver.new(client: client, config: config)
        @retry_policy    = Retry::Policy.new(config)
      end

      # Sync all records in the model's configured scope.
      # @return [Array<Result>]
      def sync_model(model_class, only_failed: false)
        model_config = model_class.airtable_sync_config
        raise ConfigurationError, "#{model_class} does not include RailsAirtableSync::Model" unless model_config

        reconcile_schema!(model_config)

        scope = only_failed ? failed_scope(model_class, model_config) : model_config.scoped_relation
        results = []

        scope.find_each(batch_size: @config.batch_size) do |record|
          result = sync_record(record, model_config: model_config)
          results << result
          raise result.error if result.failed? && @config.fail_fast && result.error
          sleep(@config.batch_sleep) if @config.batch_sleep
        end

        results
      end

      # Sync a single ActiveRecord instance.
      # @return [Result]
      def sync_record(record, model_config: nil)
        model_config ||= record.class.airtable_sync_config
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        @instrumentation.emit("airtable_sync.sync_started",
                              model:  record.class.name,
                              id:     record.id,
                              table:  model_config.table_name)

        result = perform_sync(record, model_config: model_config)
        result.duration_ms = elapsed_ms(start_time)

        emit_result_event(result)
        result
      rescue StandardError => e
        duration = elapsed_ms(start_time)
        result = Result.new(
          model_class:     record.class,
          record_id:       record.id,
          airtable_table:  model_config.table_name,
          operation:       :failed,
          checksum_changed: false,
          duration_ms:     duration,
          error:           e,
          validation_errors: []
        )
        @instrumentation.emit("airtable_sync.sync_failed",
                              model: record.class.name, id: record.id,
                              table: model_config.table_name,
                              error: e.class.name, message: e.message)
        result
      end

      private

      def perform_sync(record, model_config:)
        integrity_check!(record)

        sync_state = load_sync_state(record, model_config)

        # Build payload and checksum
        payload  = @payload_builder.build(record, model_config: model_config)
        checksum = Checksum.compute(record, model_config: model_config, serializer: @serializer)

        checksum_changed = sync_state.nil? || sync_state.payload_checksum != checksum

        # Skip if unchanged
        unless checksum_changed
          update_sync_state(sync_state, record, model_config, :synced, checksum, nil)
          return Result.new(
            model_class:      record.class,
            record_id:        record.id,
            airtable_table:   model_config.table_name,
            operation:        :skip,
            checksum_changed: false,
            airtable_record_id: sync_state.airtable_record_id,
            validation_errors: []
          )
        end

        # Resolve remote identity
        operation, airtable_record_id = @resolver.resolve(
          record, model_config: model_config, sync_record: sync_state
        )

        # Write to Airtable with retry
        returned_record = @retry_policy.with_retry do
          case operation
          when :create
            @client.create_record(model_config.table_name, payload)
          when :update
            @client.update_record(model_config.table_name, airtable_record_id, payload)
          end
        end

        airtable_record_id = returned_record["id"] if operation == :create

        # Optional post-write verification
        if @config.verify_after_write
          verify_write!(returned_record, payload, record, model_config)
        end

        # Persist sync state
        update_sync_state(sync_state, record, model_config, :synced, checksum, airtable_record_id)

        Result.new(
          model_class:       record.class,
          record_id:         record.id,
          airtable_table:    model_config.table_name,
          operation:         operation,
          checksum_changed:  true,
          airtable_record_id: airtable_record_id,
          validation_errors: []
        )
      end

      # ─── Schema reconciliation ──────────────────────────────────────────

      def reconcile_schema!(model_config)
        return unless @config.auto_manage_schema || @config.validate_remote_schema

        inspector   = Schema::Inspector.new(@client)
        reconciler  = Schema::Reconciler.new(
          client:          @client,
          inspector:       inspector,
          config:          @config,
          instrumentation: @instrumentation
        )

        schema_result = reconciler.reconcile(model_config)

        unless schema_result.ok?
          raise SchemaConflictError.new(
            "Schema reconciliation blocked sync for '#{model_config.table_name}': " \
            "#{schema_result.blocking_issues.join('; ')}",
            table_name: model_config.table_name
          )
        end
      end

      # ─── Integrity checks ───────────────────────────────────────────────

      def integrity_check!(record)
        raise ValidationError.new("Record is not persisted", record_id: record.id) unless record.persisted?
      end

      def verify_write!(returned, submitted_payload, record, model_config)
        returned_fields = returned["fields"] || {}

        submitted_payload.each do |field_name, submitted_value|
          next if model_config.mapping_for_field(field_name)&.type == :attachment_url

          remote_value = returned_fields[field_name]

          unless values_match?(submitted_value, remote_value)
            @config.logger.warn(
              "[RailsAirtableSync] verify_after_write mismatch for " \
              "#{record.class}##{record.id} field '#{field_name}': " \
              "submitted=#{submitted_value.inspect} remote=#{remote_value.inspect}"
            )
          end
        end
      end

      def values_match?(submitted, remote)
        submitted.to_s == remote.to_s
      end

      # ─── Sync state helpers ─────────────────────────────────────────────

      def load_sync_state(record, model_config)
        return nil unless @config.persist_sync_state

        State::SyncRecord.find_by(
          syncable_type:  record.class.name,
          syncable_id:    record.id,
          airtable_table: model_config.table_name
        )
      end

      def update_sync_state(sync_state, record, model_config, status, checksum, airtable_id)
        return unless @config.persist_sync_state

        attrs = {
          syncable_type:     record.class.name,
          syncable_id:       record.id,
          airtable_table:    model_config.table_name,
          status:            status,
          payload_checksum:  checksum,
          last_synced_at:    Time.current,
          last_attempted_at: Time.current,
          failure_count:     0,
          last_error_class:  nil,
          last_error_message: nil
        }
        attrs[:airtable_record_id] = airtable_id if airtable_id
        attrs[:external_key] = record.public_send(model_config.record_key).to_s

        if sync_state
          sync_state.update!(attrs)
        else
          State::SyncRecord.create!(attrs)
        end
      end

      def failed_scope(model_class, model_config)
        failed_ids = State::SyncRecord
          .where(syncable_type: model_class.name,
                 airtable_table: model_config.table_name,
                 status: %w[failed pending])
          .pluck(:syncable_id)

        model_class.where(id: failed_ids)
      end

      # ─── Instrumentation helpers ────────────────────────────────────────

      def emit_result_event(result)
        event = result.skipped? ? "airtable_sync.record_skipped" : "airtable_sync.sync_succeeded"
        @instrumentation.emit(event,
                              model:             result.model_class.name,
                              id:                result.record_id,
                              table:             result.airtable_table,
                              operation:         result.operation,
                              checksum_changed:  result.checksum_changed,
                              duration_ms:       result.duration_ms)
      end

      def elapsed_ms(start)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      end
    end
  end
end
