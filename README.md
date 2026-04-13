# rails_airtable_sync

One-way synchronisation from Rails models to Airtable. Rails is always the source of truth.

```
Rails → Airtable
```

---

## Architecture: Layer Breakdown

The gem is composed of seven discrete layers. Each layer has a single responsibility and a clear interface to adjacent layers.

```
┌─────────────────────────────────────────────────────────┐
│                    Public API / Railtie                 │
├─────────────────────────────────────────────────────────┤
│              Configuration  │  Model DSL                │
├─────────────────────────────────────────────────────────┤
│                     Sync Engine                         │
│   Checksum  │  Payload Builder  │  Record Resolver      │
├─────────────────────────────────────────────────────────┤
│   Type System / Serializer  │  Airtable Type Map        │
├─────────────────────────────────────────────────────────┤
│         Schema Reconciliation (Inspector + Reconciler)  │
├─────────────────────────────────────────────────────────┤
│               API Client  │  Retry Policy               │
├─────────────────────────────────────────────────────────┤
│         State Tracking  │  Instrumentation  │  Jobs     │
└─────────────────────────────────────────────────────────┘
```

---

### 1. Configuration Layer

**Files:** `lib/rails_airtable_sync/configuration.rb`

Holds every runtime option as typed attributes with documented defaults. Validated on Rails boot via the Railtie — misconfiguration is a hard failure, not a silent no-op.

| Option | Default | Purpose |
|---|---|---|
| `api_key` / `base_id` | — | Airtable credentials (required) |
| `strict_types` | `true` | Reject type mismatches before the API call |
| `auto_manage_schema` | `true` | Allow schema reconciliation to run |
| `auto_create_tables` | `true` | Create missing Airtable tables |
| `auto_create_fields` | `true` | Create missing Airtable fields |
| `auto_update_fields` | `true` | Extend select options, update field metadata |
| `allow_destructive_schema_changes` | `false` | Gate on field-type replacement |
| `schema_conflict_policy` | `:fail` | `:fail` \| `:ignore` \| `:replace` \| `:archive_and_replace` |
| `enable_deletes` | `false` | Opt-in to record deletion |
| `delete_strategy` | `:archive_flag` | `:none` \| `:clear_fields` \| `:archive_flag` \| `:delete_record` |
| `max_retries` | `3` | Retry cap for transient failures |
| `retry_backoff` | `:exponential` | `:exponential` \| `:linear` \| `:constant` |
| `persist_sync_state` | `true` | Write to `airtable_sync_records` table |
| `verify_after_write` | `true` | Re-read Airtable record and compare after every write |
| `sensitive_fields` | `[]` | Field names redacted from all log output |

```ruby
RailsAirtableSync.configure do |config|
  config.api_key  = ENV["AIRTABLE_API_KEY"]
  config.base_id  = ENV["AIRTABLE_BASE_ID"]
  config.logger   = Rails.logger
end
```

---

### 2. Model DSL Layer

**Files:** `lib/rails_airtable_sync/model.rb`, `lib/rails_airtable_sync/model_config.rb`, `lib/rails_airtable_sync/field_mapping.rb`

An `ActiveSupport::Concern` included in any ActiveRecord model. The `airtable_sync` class method opens a DSL block that is evaluated once at class load time and validated immediately — mapping mistakes raise `ConfigurationError` before the app starts.

Each field mapping captures:

- `airtable_field` — Airtable column name
- `from` — Rails attribute
- `type` — one of 16 canonical gem types
- `nullable` — whether nil is permitted
- `allowed_values` — enum guard for select fields
- `coerce` — opt-in permissive type coercion
- `default` — fallback when source is nil
- `omit_on_nil` — exclude field from payload entirely when nil
- `sensitive` — redact value in logs

```ruby
class Customer < ApplicationRecord
  include RailsAirtableSync::Model

  airtable_sync table: "Customers" do
    scope { where(active: true) }
    record_key        :id
    external_id_field "Rails ID"

    field "Rails ID",   from: :id,         type: :integer,       nullable: false
    field "Email",      from: :email,       type: :email,         nullable: false
    field "Full Name",  from: :full_name,   type: :string
    field "Plan",       from: :plan,        type: :single_select,
                        allowed_values: %w[free pro enterprise]

    checksum_fields :email, :full_name, :plan
  end
end
```

---

### 3. Type System / Serializer Layer

**Files:** `lib/rails_airtable_sync/type_system/`

Converts raw Rails values into Airtable-safe representations before the API is called. Each canonical type is a separate class with isolated serialisation and validation logic.

#### Supported canonical types

| Type | Airtable field type | Notes |
|---|---|---|
| `:string` | Single line text | UTF-8, optional max_length |
| `:text` | Long text | Same serialisation as `:string` |
| `:integer` | Number (precision 0) | JS-safe integer range enforced |
| `:float` | Number | Pass-through; coerce from String/Integer |
| `:decimal` | Number | BigDecimal internally; sent as float |
| `:boolean` | Checkbox | Strict: only `true`/`false`; no `"yes"` |
| `:date` | Date | ISO 8601 `YYYY-MM-DD`; normalised to UTC first |
| `:datetime` | Date/time | ISO 8601 UTC `YYYY-MM-DDTHH:MM:SSZ` |
| `:email` | Email | Format-validated before send |
| `:url` | URL | Must be `http(s)`; URI-parsed |
| `:phone` | Phone number | Pattern-validated |
| `:single_select` | Single select | Must match `allowed_values` |
| `:multi_select` | Multiple select | Array; deduplicated; validated against `allowed_values` |
| `:json` | Long text | `JSON.generate` or passthrough valid JSON string |
| `:attachment_url` | Attachments | Wraps URL(s) into `[{url: "..."}]` format |
| `:lookup_string` | Single line text | Encoding-safe stringification |
| `:formula_safe_string` | Single line text | Strips `"`, `'`, `\` |

**Strict mode** (default) rejects incompatible types before the API is called.  
**Permissive mode** (`strict_types: false` or `coerce: true` per field) applies configured coercions.

The **Airtable Type Map** (`airtable_type_map.rb`) is a separate mapping from gem types to Airtable field definition objects. It is used exclusively by the Schema Reconciliation layer — serialisation and schema definition are intentionally decoupled.

---

### 4. Schema Reconciliation Layer

**Files:** `lib/rails_airtable_sync/schema/inspector.rb`, `reconciler.rb`, `mutation_executor.rb`

Runs before record sync to ensure the remote Airtable schema can safely accept the configured mappings. All schema mutations are idempotent.

#### Inspector

Fetches the live Airtable base schema via the Metadata API and exposes `RemoteTable` and `RemoteField` structs. Results are memoised per sync run; call `reload!` to refresh.

#### Reconciler

Compares each field mapping against the live schema and produces a per-field outcome:

| Outcome | Meaning |
|---|---|
| `:ok` | Field exists and type is compatible |
| `:created` | Field was missing — created via API |
| `:updated` | Field exists — non-destructive metadata updated (e.g. new select options added) |
| `:blocked` | Change required but blocked by policy |
| `:failed` | Mutation attempted but the API call failed |

If any field is `:blocked` or `:failed`, record sync for that table is stopped.

#### Destructive change policy

Changes that could delete or corrupt Airtable data require `allow_destructive_schema_changes: true`. What is and isn't allowed by default:

| Action | Default |
|---|---|
| Create missing table | Allowed |
| Create missing field | Allowed |
| Extend select options | Allowed |
| Update compatible field metadata | Allowed |
| Delete a field | Blocked |
| Change to an incompatible type | Blocked |
| Narrow select options | Blocked |

---

### 5. Sync Engine

**Files:** `lib/rails_airtable_sync/sync/engine.rb`, `checksum.rb`, `payload_builder.rb`, `record_resolver.rb`, `result.rb`

Orchestrates the complete per-record sync workflow in 15 steps:

```
1.  Load model sync configuration
2.  Run schema reconciliation (blocks if schema is unsafe)
3.  Load Rails records from configured scope
4.  Pre-flight integrity check (record must be persisted)
5.  Build Airtable payload via PayloadBuilder
6.  Compute SHA-256 checksum over checksum_fields
7.  Compare to last synced checksum — skip write if unchanged
8.  Resolve Airtable record identity (RecordResolver)
9.  Create or update Airtable record (with retry)
10. Optionally verify: re-read and compare response to submitted payload
11. Persist sync state to airtable_sync_records
12. Emit instrumentation events
```

#### Checksum

`SHA-256` over a canonical JSON representation of checksum field values, sorted by Airtable field name. Computed post-serialisation so the checksum reflects exactly what would be sent to Airtable.

#### Record Resolver

Determines whether to `create` or `update` a remote record:

1. Check local sync state — use cached `airtable_record_id` if present.
2. Fall back to live Airtable lookup by `external_id_field` to prevent duplicates.
3. If more than one remote match is found: raise `ConsistencyError` and quarantine.

#### Result

Every sync produces a `Sync::Result` struct:

```ruby
result.operation          # :create | :update | :skip | :delete | :failed | :quarantined
result.checksum_changed   # bool
result.duration_ms        # Integer
result.airtable_record_id # String
result.error              # Exception or nil
result.success?           # bool
result.failed?            # bool
result.skipped?           # bool
```

---

### 6. API Client Layer

**Files:** `lib/rails_airtable_sync/api/client.rb`, `response.rb`

A thin Faraday-based wrapper for the Airtable REST API covering both the Records API and the Metadata API. All HTTP errors are classified and raised as typed gem errors before leaving this layer.

| HTTP status | Raised as |
|---|---|
| 429 | `RateLimitError` (retryable) |
| 401, 403 | `ApiError` (non-retryable) |
| 404, 422 | `ApiError` (non-retryable) |
| 500–504 | `ApiError` (retryable) |
| Network timeout / DNS | `TransportError` (retryable) |

---

### 7. Retry Policy

**Files:** `lib/rails_airtable_sync/retry/policy.rb`

Wraps any block with configurable retry logic. The retry layer is separate from the API client so the engine can track state between attempts.

| Error | Retryable? |
|---|---|
| `TransportError` | Yes |
| `RateLimitError` (429) | Yes |
| `ApiError` 5xx | Yes |
| `ApiError` 4xx (not 429) | No |
| `ValidationError` | No |
| `ConfigurationError` | No |

Backoff strategies:

| Strategy | Delay formula |
|---|---|
| `:exponential` | `2^(attempt-1)` seconds |
| `:linear` | `attempt` seconds |
| `:constant` | `1` second |

Optional jitter adds up to 0.5s of randomness to each delay to avoid thundering herd.

---

### 8. State Tracking Layer

**Files:** `lib/rails_airtable_sync/state/sync_record.rb`, `db/migrate/20240101000000_create_airtable_sync_records.rb`

An ActiveRecord model backed by `airtable_sync_records`. This table is the backbone for idempotency, duplicate prevention, retries, and observability.

| Column | Purpose |
|---|---|
| `syncable_type` / `syncable_id` | Polymorphic Rails record identity |
| `airtable_table` | Target Airtable table |
| `airtable_record_id` | Remote record ID (cached after first create) |
| `external_key` | Rails primary key value as string |
| `payload_checksum` | SHA-256 of last successfully synced payload |
| `last_synced_at` | Timestamp of last successful sync |
| `last_attempted_at` | Timestamp of last attempt (success or failure) |
| `last_error_class` / `last_error_message` | Persisted failure details |
| `failure_count` | Incremented on each failure; resets on success |
| `status` | `pending` \| `synced` \| `failed` \| `skipped` \| `quarantined` |

Records enter `quarantined` status when integrity cannot be guaranteed (duplicate remote matches, repeated permanent failures). Quarantined records are excluded from automatic retries until manually resolved.

---

### 9. Instrumentation Layer

**Files:** `lib/rails_airtable_sync/instrumentation.rb`

Every significant operation emits an `ActiveSupport::Notifications` event and writes a structured log line. Instrumentation errors are swallowed — they must never crash a sync.

#### Events

| Event | Fired when |
|---|---|
| `airtable_sync.sync_started` | Sync begins for a record |
| `airtable_sync.sync_succeeded` | Record created or updated successfully |
| `airtable_sync.record_skipped` | Checksum unchanged — no write needed |
| `airtable_sync.sync_failed` | Sync failed after retries exhausted |
| `airtable_sync.schema_inspection_started` | Schema fetch begins |
| `airtable_sync.schema_reconciled` | Reconciliation complete |
| `airtable_sync.schema_change_applied` | A table/field was created or updated |
| `airtable_sync.schema_drift_detected` | Remote schema differs from mapping |
| `airtable_sync.schema_conflict_detected` | Remote field type is incompatible |
| `airtable_sync.schema_change_blocked` | Mutation blocked by policy |

Subscribe to any event:

```ruby
ActiveSupport::Notifications.subscribe("airtable_sync.sync_failed") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Sentry.capture_message("Airtable sync failed", extra: event.payload)
end
```

#### Metrics

In-process counters are maintained and available via `RailsAirtableSync.instrumentation.metrics_snapshot`:

`records_synced_total`, `records_failed_total`, `records_skipped_total`, `schema_tables_created_total`, `schema_fields_created_total`, `schema_fields_updated_total`, `schema_conflicts_total`, `schema_changes_blocked_total`

---

### 10. Background Jobs

**Files:** `lib/rails_airtable_sync/jobs/sync_job.rb`, `batch_sync_job.rb`

Both jobs use `ActiveJob::Base` and inherit queue configuration from the host application.

| Job | Use case |
|---|---|
| `SyncJob` | Single record — enqueued automatically via `on: :commit` or manually |
| `BatchSyncJob` | Full model scope or failed-only re-sync |

```ruby
# Manual enqueue
RailsAirtableSync.enqueue_sync(Customer, record: customer)
RailsAirtableSync.enqueue_sync(Customer)

# Re-sync only failed records
RailsAirtableSync::Jobs::BatchSyncJob.perform_later("Customer", only_failed: true)
```

---

## Rake Tasks

```
bin/rails airtable:sync[Customer]       # Full sync for one model
bin/rails airtable:sync_all             # Full sync for all registered models
bin/rails airtable:resync_failed[Customer]  # Re-sync failed/pending records only
bin/rails airtable:verify[Customer]     # Verify without writing (planned)
```

---

## Error Hierarchy

```
RailsAirtableSync::Error
├── ConfigurationError      # Bad gem/model config — fail fast at boot
├── ValidationError         # Field-level failure before API call
│   └── SerializationError  # Type serialisation failure
├── SchemaError             # Schema inspection/mutation base
│   ├── SchemaConflictError # Remote type incompatible with mapping
│   └── SchemaMutationError # API call to create/update field failed
├── TransportError          # Network-level failure (always retryable)
├── ApiError                # Airtable HTTP error response
│   └── RateLimitError      # HTTP 429 (always retryable)
└── ConsistencyError        # Integrity violation — triggers quarantine
```

---

## Installation

Add to your `Gemfile`:

```ruby
gem "rails_airtable_sync"
```

```ruby
gem 'rails_airtable_sync', git: 'git@github.com:formulate/rails_to_airtable.git'
```

```bash
export AIRTABLE_API_KEY="your_api_key_here"
export AIRTABLE_BASE_ID="your_base_id_here"
```

Install the gem:

```ruby
bundle install
```

Find which models to sync:

Run the migration:

```
bin/rails db:migrate
```

Configure in an initializer:

```ruby
# config/initializers/airtable_sync.rb
RailsAirtableSync.configure do |config|
  config.api_key  = Rails.application.credentials.airtable_api_key
  config.base_id  = ENV["AIRTABLE_BASE_ID"]
  config.logger   = Rails.logger
end
```
