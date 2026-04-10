require "spec_helper"

RSpec.describe RailsAirtableSync::Sync::PayloadBuilder do
  let(:config)      { RailsAirtableSync.configuration }
  let(:serializer)  { RailsAirtableSync::TypeSystem::Serializer.new(config) }
  let(:builder)     { described_class.new(serializer: serializer) }
  let(:model_config) { TestCustomer.airtable_sync_config }

  def make_record(attrs = {})
    r = TestCustomer.new(
      { id: 1, email: "a@b.com", full_name: "Alice", subscribed: false }.merge(attrs)
    )
    allow(r).to receive(:persisted?).and_return(true)
    r
  end

  describe "#build" do
    it "returns a hash with Airtable field names as keys" do
      payload = builder.build(make_record, model_config: model_config)
      expect(payload).to have_key("Rails ID")
      expect(payload).to have_key("Email")
      expect(payload).to have_key("Full Name")
    end

    it "serialises email field" do
      payload = builder.build(make_record(email: "test@example.com"), model_config: model_config)
      expect(payload["Email"]).to eq "test@example.com"
    end

    it "serialises boolean field" do
      payload = builder.build(make_record(subscribed: true), model_config: model_config)
      expect(payload["Subscribed"]).to eq true
    end

    it "omits fields with omit_on_nil when value is nil" do
      # Create a config with omit_on_nil on Full Name
      model_config_local = RailsAirtableSync::ModelConfig.new(TestCustomer, "Customers")
      model_config_local.instance_eval do
        record_key :id
        external_id_field "Rails ID"
        field "Rails ID",   from: :id,        type: :integer, nullable: false
        field "Email",      from: :email,      type: :email,   nullable: false
        field "Full Name",  from: :full_name,  type: :string,  omit_on_nil: true
        checksum_fields :email
      end

      payload = builder.build(make_record(full_name: nil), model_config: model_config_local)
      expect(payload).not_to have_key("Full Name")
    end
  end
end
