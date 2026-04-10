module RailsAirtableSync
  # Holds all sync configuration for one model, built by the DSL block inside
  # `airtable_sync table: "..." do ... end`.
  class ModelConfig
    attr_reader :model_class
    attr_reader :table_name
    attr_reader :record_key        # Symbol – Rails PK attribute used as identity
    attr_reader :external_id_field # String – name of the Airtable field holding record_key
    attr_reader :field_mappings    # Array<FieldMapping>
    attr_reader :checksum_fields   # Array<Symbol> – attributes included in checksum
    attr_reader :scope_proc        # Proc or nil – AR scope for which records to sync
    attr_reader :on_commit         # bool – enqueue sync in after_commit callback

    def initialize(model_class, table_name)
      @model_class       = model_class
      @table_name        = table_name.to_s
      @record_key        = :id
      @external_id_field = nil
      @field_mappings    = []
      @checksum_fields   = []
      @scope_proc        = nil
      @on_commit         = false
    end

    # ─── DSL methods (called inside the block) ───────────────────────────────

    def scope(&block)
      @scope_proc = block
    end

    def record_key(attr)
      @record_key = attr.to_sym
    end

    def external_id_field(name)
      @external_id_field = name.to_s
    end

    def field(airtable_field, from:, type:, **options)
      mapping = FieldMapping.new(airtable_field, from: from, type: type, **options)
      if @field_mappings.any? { |m| m.airtable_field == mapping.airtable_field }
        raise ConfigurationError,
              "Duplicate field mapping '#{airtable_field}' in #{model_class}"
      end
      @field_mappings << mapping
    end

    def checksum_fields(*attrs)
      @checksum_fields = attrs.map(&:to_sym)
    end

    def on_commit(enabled = true)
      @on_commit = enabled
    end

    # ─── Derived helpers ─────────────────────────────────────────────────────

    def external_id_mapping
      @field_mappings.find { |m| m.airtable_field == @external_id_field }
    end

    def mapping_for_attr(attr)
      @field_mappings.find { |m| m.from == attr.to_sym }
    end

    def mapping_for_field(airtable_field)
      @field_mappings.find { |m| m.airtable_field == airtable_field.to_s }
    end

    def scoped_relation
      base = model_class.all
      scope_proc ? base.instance_exec(&scope_proc) : base
    end

    def validate!
      if @table_name.empty?
        raise ConfigurationError, "table name cannot be blank for #{model_class}"
      end

      if @external_id_field.nil?
        raise ConfigurationError,
              "external_id_field must be set for #{model_class}"
      end

      unless @field_mappings.any? { |m| m.airtable_field == @external_id_field }
        raise ConfigurationError,
              "No field mapping found for external_id_field '#{@external_id_field}' in #{model_class}"
      end

      if @checksum_fields.empty?
        raise ConfigurationError,
              "checksum_fields must be declared for #{model_class}"
      end

      self
    end
  end
end
