require "bundler/setup"
require "active_record"
require "active_support"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/object/blank"
require "webmock/rspec"
require "timecop"

require "rails_airtable_sync"

# ─── In-memory SQLite database for SyncRecord tests ───────────────────────────
ActiveRecord::Base.establish_connection(
  adapter:  "sqlite3",
  database: ":memory:"
)

ActiveRecord::Schema.define do
  create_table :airtable_sync_records do |t|
    t.string  :syncable_type,      null: false
    t.bigint  :syncable_id,        null: false
    t.string  :airtable_table,     null: false
    t.string  :airtable_record_id
    t.string  :external_key
    t.string  :payload_checksum
    t.datetime :last_synced_at
    t.datetime :last_attempted_at
    t.string  :last_error_class
    t.text    :last_error_message
    t.integer :failure_count,      default: 0,         null: false
    t.string  :status,             default: "pending",  null: false
    t.timestamps
  end

  add_index :airtable_sync_records,
            %i[syncable_type syncable_id airtable_table],
            unique: true,
            name:   "idx_ast_record_and_table"

  create_table :test_customers do |t|
    t.string   :email
    t.string   :full_name
    t.boolean  :subscribed, default: false
    t.datetime :created_at
  end
end

# Minimal ActiveRecord stub used in unit tests
class TestCustomer < ActiveRecord::Base
  self.table_name = "test_customers"
  include RailsAirtableSync::Model

  airtable_sync table: "Customers" do
    scope { all }
    record_key :id
    external_id_field "Rails ID"

    field "Rails ID",   from: :id,         type: :integer, nullable: false
    field "Email",      from: :email,       type: :email,   nullable: false
    field "Full Name",  from: :full_name,   type: :string
    field "Subscribed", from: :subscribed,  type: :boolean
    field "Joined",     from: :created_at,  type: :datetime

    checksum_fields :email, :full_name, :subscribed
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  config.before(:each) do
    RailsAirtableSync.reset_configuration!
    RailsAirtableSync.configure do |c|
      c.api_key  = "test_key"
      c.base_id  = "appTEST"
      c.logger   = Logger.new(nil)
      c.persist_sync_state = false
      c.auto_manage_schema = false
      c.verify_after_write = false
    end
    RailsAirtableSync::State::SyncRecord.delete_all
  end
end
