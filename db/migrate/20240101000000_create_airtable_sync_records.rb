class CreateAirtableSyncRecords < ActiveRecord::Migration[7.0]
  def change
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
      t.integer :failure_count,      default: 0,        null: false
      t.string  :status,             default: "pending", null: false

      t.timestamps
    end

    # Unique identity constraint: one sync record per Rails record per Airtable table
    add_index :airtable_sync_records,
              %i[syncable_type syncable_id airtable_table],
              unique: true,
              name:   "index_airtable_sync_records_on_record_and_table"

    # Unique external key per table (supports duplicate prevention)
    add_index :airtable_sync_records,
              %i[airtable_table external_key],
              unique: true,
              where:  "external_key IS NOT NULL",
              name:   "index_airtable_sync_records_on_table_and_external_key"

    add_index :airtable_sync_records, :status
    add_index :airtable_sync_records, :last_synced_at
    add_index :airtable_sync_records, :airtable_record_id
  end
end
