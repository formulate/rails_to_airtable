require "spec_helper"

RSpec.describe RailsAirtableSync::Sync::Engine do
  let(:client)          { instance_double(RailsAirtableSync::Api::Client) }
  let(:instrumentation) { instance_double(RailsAirtableSync::Instrumentation, emit: nil) }

  let(:engine) do
    described_class.new(
      client:          client,
      config:          RailsAirtableSync.configuration,
      instrumentation: instrumentation
    )
  end

  def make_record(attrs = {})
    r = TestCustomer.new(
      { id: 1, email: "alice@example.com", full_name: "Alice", subscribed: true }.merge(attrs)
    )
    allow(r).to receive(:persisted?).and_return(true)
    allow(r).to receive(:id).and_return(attrs.fetch(:id, 1))
    r
  end

  describe "#sync_record – create flow" do
    let(:record) { make_record }

    before do
      allow(client).to receive(:list_records).and_return([])
      allow(client).to receive(:create_record).and_return(
        { "id" => "recABC", "fields" => { "Rails ID" => 1 } }
      )
    end

    it "returns a Result with operation :create" do
      result = engine.sync_record(record)
      expect(result.operation).to eq :create
      expect(result).to be_success
    end

    it "sets airtable_record_id from API response" do
      result = engine.sync_record(record)
      expect(result.airtable_record_id).to eq "recABC"
    end
  end

  describe "#sync_record – skip flow (unchanged checksum)" do
    let(:record) { make_record }

    before do
      RailsAirtableSync.configure do |c|
        c.persist_sync_state = true
      end

      # Pre-populate a sync record with the same checksum
      serializer    = RailsAirtableSync::TypeSystem::Serializer.new(RailsAirtableSync.configuration)
      checksum      = RailsAirtableSync::Sync::Checksum.compute(
        record,
        model_config: TestCustomer.airtable_sync_config,
        serializer:   serializer
      )

      RailsAirtableSync::State::SyncRecord.create!(
        syncable_type:     "TestCustomer",
        syncable_id:       record.id,
        airtable_table:    "Customers",
        airtable_record_id: "recEXIST",
        payload_checksum:  checksum,
        status:            "synced",
        failure_count:     0
      )
    end

    it "returns :skip and does not call the API" do
      expect(client).not_to receive(:update_record)
      expect(client).not_to receive(:create_record)

      result = engine.sync_record(record)
      expect(result.operation).to eq :skip
      expect(result.checksum_changed).to be false
    end
  end

  describe "#sync_record – update flow" do
    let(:record) { make_record(email: "updated@example.com") }

    before do
      RailsAirtableSync.configure do |c|
        c.persist_sync_state = true
      end

      RailsAirtableSync::State::SyncRecord.create!(
        syncable_type:     "TestCustomer",
        syncable_id:       record.id,
        airtable_table:    "Customers",
        airtable_record_id: "recEXIST",
        payload_checksum:  "old_checksum",
        status:            "synced",
        failure_count:     0
      )

      allow(client).to receive(:update_record).and_return(
        { "id" => "recEXIST", "fields" => { "Email" => "updated@example.com" } }
      )
    end

    it "returns :update result" do
      result = engine.sync_record(record)
      expect(result.operation).to eq :update
      expect(result.airtable_record_id).to eq "recEXIST"
    end
  end

  describe "#sync_record – API transport error with retry" do
    let(:record) { make_record }

    before do
      allow(client).to receive(:list_records).and_return([])
      call_count = 0
      allow(client).to receive(:create_record) do
        call_count += 1
        raise RailsAirtableSync::TransportError, "timeout" if call_count < 2
        { "id" => "recNEW", "fields" => {} }
      end
      # Speed up retry in tests
      allow_any_instance_of(RailsAirtableSync::Retry::Policy).to receive(:sleep)
    end

    it "retries and succeeds" do
      result = engine.sync_record(record)
      expect(result.operation).to eq :create
    end
  end

  describe "#sync_record – validation error" do
    let(:record) { make_record(email: "not-valid") }

    it "returns a failed Result without calling the API" do
      expect(client).not_to receive(:create_record)
      result = engine.sync_record(record)
      expect(result).to be_failed
      expect(result.error).to be_a(RailsAirtableSync::ValidationError)
    end
  end

  describe "#sync_record – rate limit (429)" do
    let(:record) { make_record }

    before do
      allow(client).to receive(:list_records).and_return([])
      allow(client).to receive(:create_record)
        .and_raise(RailsAirtableSync::RateLimitError)
      allow_any_instance_of(RailsAirtableSync::Retry::Policy).to receive(:sleep)
    end

    it "retries and eventually fails with RateLimitError" do
      result = engine.sync_record(record)
      expect(result).to be_failed
      expect(result.error).to be_a(RailsAirtableSync::RateLimitError)
    end
  end
end
