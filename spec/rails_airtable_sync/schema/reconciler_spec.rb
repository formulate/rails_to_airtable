require "spec_helper"

RSpec.describe RailsAirtableSync::Schema::Reconciler do
  let(:client)          { instance_double(RailsAirtableSync::Api::Client) }
  let(:instrumentation) { instance_double(RailsAirtableSync::Instrumentation, emit: nil) }
  let(:inspector)       { instance_double(RailsAirtableSync::Schema::Inspector) }
  let(:model_config)    { TestCustomer.airtable_sync_config }

  def build_reconciler(allow_destructive: false, conflict_policy: :fail,
                       auto_create_tables: true, auto_create_fields: true,
                       auto_update_fields: true)
    RailsAirtableSync.configure do |c|
      c.auto_manage_schema                = true
      c.auto_create_tables                = auto_create_tables
      c.auto_create_fields                = auto_create_fields
      c.auto_update_fields                = auto_update_fields
      c.allow_destructive_schema_changes  = allow_destructive
      c.schema_conflict_policy            = conflict_policy
    end

    described_class.new(
      client:          client,
      inspector:       inspector,
      config:          RailsAirtableSync.configuration,
      instrumentation: instrumentation
    )
  end

  def remote_field(name, type)
    RailsAirtableSync::Schema::Inspector::RemoteField.new(
      id: "fld#{name}", name: name, type: type, options: {}
    )
  end

  def remote_table(name, fields)
    RailsAirtableSync::Schema::Inspector::RemoteTable.new(
      id: "tbl123", name: name, fields: fields
    )
  end

  describe "when all fields are present and compatible" do
    it "returns :ok for all fields and result.ok? is true" do
      fields = [
        remote_field("Rails ID",   "number"),
        remote_field("Email",      "email"),
        remote_field("Full Name",  "singleLineText"),
        remote_field("Subscribed", "checkbox"),
        remote_field("Joined",     "dateTime")
      ]
      table = remote_table("Customers", fields)

      allow(inspector).to receive(:find_table).with("Customers").and_return(table)

      result = build_reconciler.reconcile(model_config)
      expect(result.ok?).to be true
      result.field_outcomes.each_value do |outcome|
        expect(outcome[:status]).to eq :ok
      end
    end
  end

  describe "when a field is missing" do
    let(:existing_fields) do
      [
        remote_field("Rails ID",   "number"),
        remote_field("Email",      "email"),
        remote_field("Subscribed", "checkbox"),
        remote_field("Joined",     "dateTime")
      ]
    end
    let(:table) { remote_table("Customers", existing_fields) }

    before do
      allow(inspector).to receive(:find_table).with("Customers").and_return(table)
    end

    it "creates the missing field when auto_create_fields is true" do
      allow(client).to receive(:create_field).and_return({})
      result = build_reconciler.reconcile(model_config)
      expect(result.field_outcomes["Full Name"][:status]).to eq :created
    end

    it "returns :blocked when auto_create_fields is false" do
      result = build_reconciler(auto_create_fields: false).reconcile(model_config)
      expect(result.field_outcomes["Full Name"][:status]).to eq :blocked
    end

    it "raises SchemaConflictError when conflict_policy is :fail and field is blocked" do
      reconciler = build_reconciler(auto_create_fields: false, conflict_policy: :fail)
      expect { reconciler.reconcile(model_config) }
        .to raise_error(RailsAirtableSync::SchemaConflictError)
    end
  end

  describe "when table is missing" do
    before do
      allow(inspector).to receive(:find_table).with("Customers").and_return(nil)
    end

    it "creates the table when auto_create_tables is true" do
      allow(client).to receive(:create_table).and_return({})
      allow(inspector).to receive(:reload!).and_return(inspector)
      allow(inspector).to receive(:find_table).with("Customers").and_return(
        remote_table("Customers", [
          remote_field("Rails ID",   "number"),
          remote_field("Email",      "email"),
          remote_field("Full Name",  "singleLineText"),
          remote_field("Subscribed", "checkbox"),
          remote_field("Joined",     "dateTime")
        ])
      )
      result = build_reconciler.reconcile(model_config)
      expect(result.table_outcome).to eq :created
    end

    it "returns :blocked when auto_create_tables is false" do
      result = build_reconciler(auto_create_tables: false).reconcile(model_config)
      expect(result.table_outcome).to eq :blocked
    end
  end

  describe "when a field has an incompatible type" do
    let(:fields) do
      [
        remote_field("Rails ID",   "number"),
        remote_field("Email",      "multilineText"),  # incompatible — email field expects :email
        remote_field("Full Name",  "singleLineText"),
        remote_field("Subscribed", "checkbox"),
        remote_field("Joined",     "dateTime")
      ]
    end

    before do
      allow(inspector).to receive(:find_table).with("Customers").and_return(
        remote_table("Customers", fields)
      )
    end

    it "returns :blocked for the incompatible field by default" do
      result = build_reconciler.reconcile(model_config)
      expect(result.field_outcomes["Email"][:status]).to eq :blocked
    end

    it "raises SchemaConflictError when conflict_policy is :fail" do
      expect { build_reconciler(conflict_policy: :fail).reconcile(model_config) }
        .to raise_error(RailsAirtableSync::SchemaConflictError)
    end
  end
end
