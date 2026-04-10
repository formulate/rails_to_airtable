require "spec_helper"

RSpec.describe RailsAirtableSync::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "sets safe defaults for all boolean flags" do
      expect(config.enable_deletes).to be false
      expect(config.strict_types).to be true
      expect(config.auto_manage_schema).to be true
      expect(config.auto_create_tables).to be true
      expect(config.auto_create_fields).to be true
      expect(config.auto_update_fields).to be true
      expect(config.allow_destructive_schema_changes).to be false
    end

    it "defaults to exponential backoff with jitter" do
      expect(config.retry_backoff).to eq :exponential
      expect(config.retry_jitter).to be true
      expect(config.max_retries).to eq 3
    end

    it "defaults schema_conflict_policy to :fail" do
      expect(config.schema_conflict_policy).to eq :fail
    end

    it "defaults delete_strategy to :archive_flag" do
      expect(config.delete_strategy).to eq :archive_flag
    end
  end

  describe "#validate!" do
    before do
      config.api_key = "key"
      config.base_id = "base"
    end

    it "passes with valid config" do
      expect { config.validate! }.not_to raise_error
    end

    it "raises when api_key is nil" do
      config.api_key = nil
      expect { config.validate! }.to raise_error(RailsAirtableSync::ConfigurationError, /api_key/)
    end

    it "raises when base_id is empty" do
      config.base_id = ""
      expect { config.validate! }.to raise_error(RailsAirtableSync::ConfigurationError, /base_id/)
    end

    it "raises for unknown retry_backoff" do
      config.retry_backoff = :magic
      expect { config.validate! }.to raise_error(RailsAirtableSync::ConfigurationError, /retry_backoff/)
    end

    it "raises for unknown schema_conflict_policy" do
      config.schema_conflict_policy = :destroy_everything
      expect { config.validate! }.to raise_error(RailsAirtableSync::ConfigurationError, /schema_conflict_policy/)
    end
  end

  describe "#redacted?" do
    it "returns false when no sensitive fields configured" do
      expect(config.redacted?("email")).to be false
    end

    it "returns true for configured sensitive field" do
      config.sensitive_fields = ["email", "ssn"]
      expect(config.redacted?("email")).to be true
      expect(config.redacted?(:ssn)).to be true
      expect(config.redacted?("full_name")).to be false
    end
  end
end
