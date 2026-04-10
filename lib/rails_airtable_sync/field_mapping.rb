module RailsAirtableSync
  # Represents the configuration for a single field mapping between a Rails
  # model attribute and an Airtable column.
  class FieldMapping
    SUPPORTED_TYPES = %i[
      string text integer float decimal boolean
      date datetime email url phone
      single_select multi_select
      json attachment_url lookup_string formula_safe_string
    ].freeze

    attr_reader :airtable_field   # Airtable column name (String)
    attr_reader :from             # Rails attribute name (Symbol)
    attr_reader :type             # Canonical gem type (Symbol)
    attr_reader :nullable         # bool – whether nil is allowed
    attr_reader :allowed_values   # for single_select / multi_select
    attr_reader :coerce           # bool – allow permissive coercion
    attr_reader :default          # fallback value when source is nil
    attr_reader :omit_on_nil     # skip the field in payload when nil
    attr_reader :max_length       # optional max byte length for strings
    attr_reader :sensitive        # bool – redact in logs

    def initialize(airtable_field, from:, type:, nullable: true,
                   allowed_values: nil, coerce: false, default: nil,
                   omit_on_nil: false, max_length: nil, sensitive: false)
      @airtable_field = airtable_field.to_s
      @from           = from.to_sym
      @type           = type.to_sym
      @nullable       = nullable
      @allowed_values = allowed_values&.map(&:to_s)
      @coerce         = coerce
      @default        = default
      @omit_on_nil    = omit_on_nil
      @max_length     = max_length
      @sensitive      = sensitive

      validate_type!
    end

    def sensitive? = @sensitive
    def nullable?  = @nullable
    def coerce?    = @coerce

    private

    def validate_type!
      return if SUPPORTED_TYPES.include?(@type)

      raise ConfigurationError,
            "Unknown field type :#{@type} for '#{@airtable_field}'. " \
            "Supported: #{SUPPORTED_TYPES.join(', ')}"
    end
  end
end
