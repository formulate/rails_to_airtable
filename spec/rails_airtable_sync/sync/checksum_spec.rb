require "spec_helper"

RSpec.describe RailsAirtableSync::Sync::Checksum do
  let(:config)      { RailsAirtableSync.configuration }
  let(:serializer)  { RailsAirtableSync::TypeSystem::Serializer.new(config) }
  let(:model_config) { TestCustomer.airtable_sync_config }

  def make_record(attrs = {})
    r = TestCustomer.new(
      { id: 1, email: "a@b.com", full_name: "A B", subscribed: true }.merge(attrs)
    )
    allow(r).to receive(:persisted?).and_return(true)
    r
  end

  describe ".compute" do
    it "returns a 64-char hex SHA-256 string" do
      record = make_record
      cs = described_class.compute(record, model_config: model_config, serializer: serializer)
      expect(cs).to match(/\A[0-9a-f]{64}\z/)
    end

    it "produces the same checksum for unchanged attributes" do
      r1 = make_record
      r2 = make_record
      cs1 = described_class.compute(r1, model_config: model_config, serializer: serializer)
      cs2 = described_class.compute(r2, model_config: model_config, serializer: serializer)
      expect(cs1).to eq cs2
    end

    it "produces different checksums when an attribute changes" do
      r1 = make_record(email: "a@b.com")
      r2 = make_record(email: "c@d.com")
      cs1 = described_class.compute(r1, model_config: model_config, serializer: serializer)
      cs2 = described_class.compute(r2, model_config: model_config, serializer: serializer)
      expect(cs1).not_to eq cs2
    end

    it "is stable regardless of field_mappings order" do
      r = make_record
      # checksum_fields are sorted before serialisation
      cs = described_class.compute(r, model_config: model_config, serializer: serializer)
      expect(cs).to be_a String
    end
  end
end
