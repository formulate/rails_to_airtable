module RailsAirtableSync
  module Schema
    # Compares a ModelConfig's field mappings to the live Airtable schema and
    # produces a reconciliation plan.  Optionally executes schema mutations via
    # MutationExecutor.
    #
    # Possible per-field outcomes:
    #   :ok       – field exists and is compatible, no action needed
    #   :created  – field was missing and was created
    #   :updated  – field was present but metadata was updated
    #   :blocked  – change is destructive and allow_destructive_schema_changes = false
    #   :failed   – mutation attempted but failed
    class Reconciler
      Result = Struct.new(:table_name, :field_outcomes, :table_outcome, :blocking_issues,
                          keyword_init: true) do
        def ok?
          blocking_issues.empty? &&
            field_outcomes.none? { |_, outcome| %i[blocked failed].include?(outcome[:status]) }
        end
      end

      def initialize(client:, inspector:, config:, instrumentation:)
        @client          = client
        @inspector       = inspector
        @config          = config
        @instrumentation = instrumentation
        @executor        = MutationExecutor.new(client: client)
      end

      # Reconcile schema for a single ModelConfig.
      # Returns a Result.  Raises if reconciliation is required but fails and
      # schema_conflict_policy is :fail.
      def reconcile(model_config)
        table_name   = model_config.table_name
        field_outcomes = {}
        blocking_issues = []

        @instrumentation.emit("airtable_sync.schema_inspection_started", table: table_name)

        remote_table = @inspector.find_table(table_name)
        table_outcome = reconcile_table(remote_table, table_name, model_config)

        if table_outcome == :failed
          blocking_issues << "Could not create or find table '#{table_name}'"
          return Result.new(
            table_name:      table_name,
            field_outcomes:  {},
            table_outcome:   :failed,
            blocking_issues: blocking_issues
          )
        end

        # Re-fetch if table was just created
        remote_table = @inspector.reload!.find_table(table_name) if table_outcome == :created

        model_config.field_mappings.each do |mapping|
          outcome = reconcile_field(mapping, remote_table, table_name)
          field_outcomes[mapping.airtable_field] = outcome

          if %i[blocked failed].include?(outcome[:status])
            blocking_issues << "Field '#{mapping.airtable_field}': #{outcome[:reason]}"
          end
        end

        result = Result.new(
          table_name:      table_name,
          field_outcomes:  field_outcomes,
          table_outcome:   table_outcome,
          blocking_issues: blocking_issues
        )

        @instrumentation.emit("airtable_sync.schema_reconciled",
                              table: table_name,
                              ok: result.ok?,
                              field_outcomes: field_outcomes.transform_values { |o| o[:status] })

        if result.ok?
          result
        else
          handle_blocking_issues!(blocking_issues, table_name)
          result
        end
      end

      private

      # ─── Table-level ─────────────────────────────────────────────────────

      def reconcile_table(remote_table, table_name, model_config)
        if remote_table
          @instrumentation.emit("airtable_sync.schema_inspection_started",
                                table: table_name, action: :found)
          return :ok
        end

        unless @config.auto_manage_schema && @config.auto_create_tables
          @instrumentation.emit("airtable_sync.schema_change_blocked",
                                table: table_name, action: :create_table,
                                reason: "auto_create_tables disabled")
          return :blocked
        end

        @instrumentation.emit("airtable_sync.schema_change_applied",
                              table: table_name, action: :create_table)
        create_table(table_name, model_config)
      end

      def create_table(table_name, model_config)
        initial_fields = model_config.field_mappings.map do |m|
          TypeSystem::AirtableTypeMap.field_definition(m)
        end
        @executor.create_table(table_name, fields: initial_fields)
        :created
      rescue SchemaMutationError => e
        @instrumentation.emit("airtable_sync.schema_change_blocked",
                              table: table_name, action: :create_table, error: e.message)
        :failed
      end

      # ─── Field-level ─────────────────────────────────────────────────────

      def reconcile_field(mapping, remote_table, table_name)
        remote_field = remote_table&.field_by_name(mapping.airtable_field)
        expected     = TypeSystem::AirtableTypeMap.for_type(mapping.type)

        if remote_field.nil?
          return create_field(mapping, remote_table, table_name)
        end

        if TypeSystem::AirtableTypeMap.compatible?(mapping.type, remote_field.type)
          outcome = maybe_update_field(mapping, remote_field, remote_table, table_name)
          @instrumentation.emit("airtable_sync.schema_reconciled",
                                table: table_name, field: mapping.airtable_field,
                                action: outcome[:status])
          outcome
        else
          handle_incompatible_field(mapping, remote_field, remote_table, table_name, expected)
        end
      end

      def create_field(mapping, remote_table, table_name)
        unless @config.auto_manage_schema && @config.auto_create_fields
          msg = "auto_create_fields disabled; field '#{mapping.airtable_field}' missing"
          @instrumentation.emit("airtable_sync.schema_change_blocked",
                                table: table_name, field: mapping.airtable_field,
                                reason: msg)
          return { status: :blocked, reason: msg }
        end

        definition = TypeSystem::AirtableTypeMap.field_definition(mapping)
        @executor.create_field(remote_table.id, definition)
        @instrumentation.emit("airtable_sync.schema_change_applied",
                              table: table_name, field: mapping.airtable_field,
                              action: :create_field)
        { status: :created }
      rescue SchemaMutationError => e
        @instrumentation.emit("airtable_sync.schema_change_blocked",
                              table: table_name, field: mapping.airtable_field, error: e.message)
        { status: :failed, reason: e.message }
      end

      def maybe_update_field(mapping, remote_field, remote_table, table_name)
        return { status: :ok } unless @config.auto_manage_schema && @config.auto_update_fields

        updates = compute_safe_updates(mapping, remote_field)
        return { status: :ok } if updates.empty?

        @executor.update_field(remote_table.id, remote_field.id, updates)
        @instrumentation.emit("airtable_sync.schema_change_applied",
                              table: table_name, field: mapping.airtable_field,
                              action: :update_field, updates: updates)
        { status: :updated }
      rescue SchemaMutationError => e
        { status: :failed, reason: e.message }
      end

      def handle_incompatible_field(mapping, remote_field, remote_table, table_name, expected)
        msg = "Field '#{mapping.airtable_field}' has remote type '#{remote_field.type}' " \
              "but config expects '#{expected[:airtable_type]}'"

        @instrumentation.emit("airtable_sync.schema_conflict_detected",
                              table: table_name, field: mapping.airtable_field,
                              remote_type: remote_field.type,
                              expected_type: expected[:airtable_type])

        unless @config.allow_destructive_schema_changes
          @instrumentation.emit("airtable_sync.schema_change_blocked",
                                table: table_name, field: mapping.airtable_field, reason: msg)
          return { status: :blocked, reason: msg }
        end

        case @config.schema_conflict_policy
        when :ignore
          { status: :ok, reason: "ignored per schema_conflict_policy" }
        when :replace, :archive_and_replace
          # Destructive — requires explicit opt-in
          attempt_replace(mapping, remote_field, remote_table, table_name)
        else
          { status: :blocked, reason: msg }
        end
      end

      def attempt_replace(mapping, remote_field, remote_table, table_name)
        # For safety: archive the old field name by appending _deprecated,
        # then create the new field.
        if @config.schema_conflict_policy == :archive_and_replace
          @executor.update_field(remote_table.id, remote_field.id,
                                 { name: "#{remote_field.name}_deprecated_#{Time.now.to_i}" })
        end

        definition = TypeSystem::AirtableTypeMap.field_definition(mapping)
        @executor.create_field(remote_table.id, definition)
        @instrumentation.emit("airtable_sync.schema_change_applied",
                              table: table_name, field: mapping.airtable_field,
                              action: :replace_field)
        { status: :created }
      rescue SchemaMutationError => e
        { status: :failed, reason: e.message }
      end

      # Compute non-destructive option updates (e.g. adding new select choices).
      def compute_safe_updates(mapping, remote_field)
        updates = {}

        if %i[single_select multi_select].include?(mapping.type) &&
           mapping.allowed_values&.any?
          existing_choices = Array(remote_field.options["choices"]).map { |c| c["name"] }
          new_choices      = mapping.allowed_values - existing_choices

          unless new_choices.empty?
            updates[:options] = {
              choices: (existing_choices + new_choices).map { |v| { name: v } }
            }
          end
        end

        updates
      end

      def handle_blocking_issues!(blocking_issues, table_name)
        return if blocking_issues.empty?

        case @config.schema_conflict_policy
        when :fail
          raise SchemaConflictError.new(
            "Schema reconciliation failed for table '#{table_name}': #{blocking_issues.join('; ')}",
            table_name: table_name
          )
        end
        # :ignore, :replace, :archive_and_replace — already handled per-field above
      end
    end
  end
end
