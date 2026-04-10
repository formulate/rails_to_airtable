module RailsAirtableSync
  # Base class for all gem errors.
  class Error < StandardError; end

  # Raised when the gem or model configuration is invalid (missing API key,
  # unknown field type, duplicate mapping, etc.).  Fail-fast on startup.
  class ConfigurationError < Error; end

  # Raised when a field value fails validation before the API call is made
  # (e.g. nil in a non-nullable field, bad enum value, invalid email).
  class ValidationError < Error
    attr_reader :model, :record_id, :field_name, :raw_value, :expected_type

    def initialize(message, model: nil, record_id: nil, field_name: nil,
                   raw_value: nil, expected_type: nil)
      super(message)
      @model         = model
      @record_id     = record_id
      @field_name    = field_name
      @raw_value     = raw_value
      @expected_type = expected_type
    end

    def to_h
      {
        model:         model,
        record_id:     record_id,
        field_name:    field_name,
        raw_value:     raw_value,
        expected_type: expected_type,
        message:       message
      }
    end
  end

  # Raised when a value cannot be serialized to an Airtable-compatible format.
  class SerializationError < ValidationError; end

  # Base for schema-related failures.
  class SchemaError < Error; end

  # Raised when a remote Airtable field/table exists but is incompatible with
  # the configured mapping and the conflict policy is :fail.
  class SchemaConflictError < SchemaError
    attr_reader :table_name, :field_name, :remote_type, :expected_type

    def initialize(message, table_name: nil, field_name: nil,
                   remote_type: nil, expected_type: nil)
      super(message)
      @table_name    = table_name
      @field_name    = field_name
      @remote_type   = remote_type
      @expected_type = expected_type
    end
  end

  # Raised when a schema mutation (create table/field, update field) fails.
  class SchemaMutationError < SchemaError; end

  # Raised for network-level failures (timeout, connection reset, DNS).
  # These are always considered retryable.
  class TransportError < Error; end

  # Raised for Airtable API HTTP error responses (4xx / 5xx).
  class ApiError < Error
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body   = body
    end

    def retryable?
      status.nil? || status == 429 || status >= 500
    end
  end

  # Raised specifically for HTTP 429 Too Many Requests.
  class RateLimitError < ApiError
    def initialize(message = "Airtable rate limit exceeded (429)", **kwargs)
      super(message, status: 429, **kwargs)
    end

    def retryable? = true
  end

  # Raised when local mapping integrity cannot be guaranteed (e.g. duplicate
  # external IDs found in Airtable, unexpected response structure, missing
  # remote record).  Records in this state are quarantined.
  class ConsistencyError < Error; end
end
