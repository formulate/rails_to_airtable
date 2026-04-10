require "spec_helper"

RSpec.describe RailsAirtableSync::Model do
  describe "airtable_sync DSL" do
    subject(:model_config) { TestCustomer.airtable_sync_config }

    it "exposes the table name" do
      expect(model_config.table_name).to eq "Customers"
    end

    it "registers the correct external_id_field" do
      expect(model_config.external_id_field).to eq "Rails ID"
    end

    it "has 5 field mappings" do
      expect(model_config.field_mappings.size).to eq 5
    end

    it "maps 'Email' from :email as :email type" do
      m = model_config.mapping_for_field("Email")
      expect(m).not_to be_nil
      expect(m.from).to eq :email
      expect(m.type).to eq :email
    end

    it "marks 'Rails ID' as non-nullable" do
      m = model_config.mapping_for_field("Rails ID")
      expect(m.nullable?).to be false
    end

    it "registers 3 checksum fields" do
      expect(model_config.checksum_fields).to contain_exactly(:email, :full_name, :subscribed)
    end

    it "registers the model in the global registry" do
      expect(RailsAirtableSync.registered_models).to include(TestCustomer)
    end
  end

  describe "missing external_id_field" do
    it "raises ConfigurationError at class load time" do
      expect {
        Class.new(ActiveRecord::Base) do
          include RailsAirtableSync::Model
          self.table_name = "test_customers"

          airtable_sync table: "No External" do
            record_key :id
            field "Name", from: :name, type: :string
            checksum_fields :name
            # external_id_field intentionally omitted
          end
        end
      }.to raise_error(RailsAirtableSync::ConfigurationError, /external_id_field/)
    end
  end

  describe "unknown field type" do
    it "raises ConfigurationError" do
      expect {
        RailsAirtableSync::FieldMapping.new("X", from: :x, type: :widget)
      }.to raise_error(RailsAirtableSync::ConfigurationError, /widget/)
    end
  end

  describe "duplicate field mapping" do
    it "raises ConfigurationError" do
      expect {
        Class.new(ActiveRecord::Base) do
          include RailsAirtableSync::Model
          self.table_name = "test_customers"

          airtable_sync table: "Dups" do
            record_key :id
            external_id_field "ID"
            field "ID",   from: :id,    type: :integer, nullable: false
            field "ID",   from: :email, type: :string   # duplicate
            checksum_fields :id
          end
        end
      }.to raise_error(RailsAirtableSync::ConfigurationError, /Duplicate/)
    end
  end
end
