# Installation Guide

## Requirements

- Ruby >= 3.1
- Rails >= 7.0
- An Airtable account with a Personal Access Token that has the following scopes:
  - `data.records:read`
  - `data.records:write`
  - `schema.bases:read`
  - `schema.bases:write` _(only required if `auto_manage_schema` is enabled, which is the default)_

---

## Step 1 — Add the gem

Add to your application's `Gemfile`:

```ruby
gem "rails_airtable_sync"
```

Then run:

```
bundle install
```

---

## Step 2 — Store your credentials

Never hard-code your Airtable API key. Use one of these approaches:

**Option A — Rails credentials (recommended)**

```
bin/rails credentials:edit
```

```yaml
airtable:
  api_key: pat_xxxxxxxxxxxxxxxxxxxx
  base_id: appXXXXXXXXXXXXXX
```

**Option B — Environment variables**

```bash
export AIRTABLE_API_KEY="pat_xxxxxxxxxxxxxxxxxxxx"
export AIRTABLE_BASE_ID="appXXXXXXXXXXXXXX"
```

Your Personal Access Token is found in Airtable under **Account → Developer hub → Personal access tokens**. Your Base ID is in the URL when you open a base: `https://airtable.com/appXXXXXXXXXXXXXX/...`

---

## Step 3 — Run the migration

The gem needs one table in your database to track sync state:

```
bin/rails db:migrate
```

This creates `airtable_sync_records` with indexes for idempotency, retries, and observability. If you need to inspect or customise the migration before running it, find it at:

```
db/migrate/20240101000000_create_airtable_sync_records.rb
```

---

## Step 4 — Create an initializer

```
touch config/initializers/airtable_sync.rb
```

Minimal configuration:

```ruby
# config/initializers/airtable_sync.rb
RailsAirtableSync.configure do |config|
  config.api_key = Rails.application.credentials.dig(:airtable, :api_key)
  config.base_id = Rails.application.credentials.dig(:airtable, :base_id)
  config.logger  = Rails.logger
end
```

The gem validates credentials on boot. A missing or blank `api_key` or `base_id` raises `RailsAirtableSync::ConfigurationError` immediately, so misconfiguration is caught before your app accepts traffic.

**Full configuration reference** (all values shown are the defaults):

```ruby
RailsAirtableSync.configure do |config|
  # Required
  config.api_key = Rails.application.credentials.dig(:airtable, :api_key)
  config.base_id = Rails.application.credentials.dig(:airtable, :base_id)

  # HTTP timeouts (seconds)
  config.timeout      = 10
  config.open_timeout = 3

  # Retry
  config.max_retries   = 3
  config.retry_backoff = :exponential  # :exponential | :linear | :constant
  config.retry_jitter  = true

  # Type enforcement
  config.strict_types = true  # false enables permissive coercion

  # Schema management
  config.auto_manage_schema               = true
  config.auto_create_tables               = true
  config.auto_create_fields               = true
  config.auto_update_fields               = true
  config.allow_destructive_schema_changes = false
  config.schema_conflict_policy           = :fail  # :fail | :ignore | :replace | :archive_and_replace

  # Record deletion (off by default)
  config.enable_deletes  = false
  config.delete_strategy = :archive_flag  # :none | :clear_fields | :archive_flag | :delete_record

  # Integrity
  config.verify_after_write     = true
  config.validate_remote_schema = true

  # State persistence
  config.persist_sync_state = true
  config.use_advisory_locks = true

  # Error behaviour
  config.fail_fast            = false
  config.on_validation_error  = :mark_failed  # :mark_failed | :raise | :skip
  config.on_consistency_error = :quarantine   # :quarantine | :raise | :skip

  # Observability
  config.logger           = Rails.logger
  config.sensitive_fields = []  # field names redacted in all log output

  # Batching
  config.batch_size  = 100
  config.batch_sleep = nil  # seconds to sleep between batches
end
```

---

## Step 5 — Add the mapping to your model

Include `RailsAirtableSync::Model` and declare your mapping in an `airtable_sync` block:

```ruby
class Customer < ApplicationRecord
  include RailsAirtableSync::Model

  airtable_sync table: "Customers" do
    scope { where(active: true) }

    record_key        :id
    external_id_field "Rails ID"

    field "Rails ID",   from: :id,         type: :integer, nullable: false
    field "Email",      from: :email,       type: :email,   nullable: false
    field "Full Name",  from: :full_name,   type: :string
    field "Subscribed", from: :subscribed,  type: :boolean
    field "Joined At",  from: :created_at,  type: :datetime

    checksum_fields :email, :full_name, :subscribed, :created_at
  end
end
```

`external_id_field` must name an Airtable column that stores the Rails primary key. This is what the gem uses to find existing records and prevent duplicates.

`checksum_fields` controls which attributes are included in the change-detection hash. Only records whose checksum has changed since the last sync are written to Airtable.

---

## Step 6 — Run your first sync

**From the console:**

```ruby
RailsAirtableSync.sync(Customer)
```

**From a rake task:**

```
bin/rails airtable:sync[Customer]
```

**Sync all registered models:**

```
bin/rails airtable:sync_all
```

**Sync a single record (e.g. after saving):**

```ruby
RailsAirtableSync.sync(Customer, record: customer)
```

---

## Step 7 — (Optional) Enable automatic sync on save

Add `on: :commit` inside the `airtable_sync` block to enqueue a background job after every committed write:

```ruby
airtable_sync table: "Customers" do
  on :commit

  # ... rest of mapping
end
```

This requires ActiveJob to be configured with a real queue adapter (not `:inline` in production). The job class is `RailsAirtableSync::Jobs::SyncJob`.

---

## Step 8 — (Optional) Re-sync failed records

Records that fail are kept in `airtable_sync_records` with `status = "failed"`. Re-run them without touching successfully synced records:

```
bin/rails airtable:resync_failed[Customer]
```

Or via ActiveJob:

```ruby
RailsAirtableSync::Jobs::BatchSyncJob.perform_later("Customer", only_failed: true)
```

---

## Troubleshooting

**`ConfigurationError: api_key must be set`**
Your initializer is not being loaded, or the credential path is wrong. Verify with `Rails.application.credentials.dig(:airtable, :api_key)` in the console.

**`SchemaConflictError` on first sync**
The Airtable table already exists with a field whose type is incompatible with your mapping. Check the log for `schema_conflict_detected` events. Either update the Airtable field type manually, or set `config.allow_destructive_schema_changes = true` and `config.schema_conflict_policy = :replace` to let the gem fix it automatically.

**`ConsistencyError: Found N Airtable records with ...`**
There are duplicate records in Airtable for the same `external_id_field` value. Delete the duplicates in Airtable manually, then clear the quarantine:

```ruby
RailsAirtableSync::State::SyncRecord
  .where(syncable_type: "Customer", status: "quarantined")
  .update_all(status: "pending", failure_count: 0)
```

**Records are being skipped unexpectedly**
The payload checksum matches the last synced state. If you changed your `checksum_fields` list, force a re-sync by clearing checksums:

```ruby
RailsAirtableSync::State::SyncRecord
  .where(syncable_type: "Customer")
  .update_all(payload_checksum: nil)
```

**Rate limit errors (429)**
The gem retries 429 responses automatically with exponential backoff. If you are hitting the limit consistently during bulk syncs, lower `batch_size` and add a `batch_sleep` delay:

```ruby
config.batch_size  = 25
config.batch_sleep = 0.25  # seconds between batches
```
