require "spec_helper"

RSpec.describe RailsAirtableSync::Api::Client do
  let(:config) { RailsAirtableSync.configuration }
  let(:client) { described_class.new(config) }

  before { WebMock.enable! }
  after  { WebMock.reset! }

  let(:base_url) { "https://api.airtable.com/v0/appTEST/Customers" }

  describe "#list_records" do
    it "returns records from API response" do
      stub_request(:get, base_url)
        .to_return(
          status: 200,
          body:   { records: [{ id: "rec1", fields: { "Email" => "a@b.com" } }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      records = client.list_records("Customers")
      expect(records.size).to eq 1
      expect(records.first["id"]).to eq "rec1"
    end

    it "handles pagination by following offset" do
      stub_request(:get, base_url)
        .with(query: hash_including("pageSize" => "100"))
        .to_return(
          status: 200,
          body:   { records: [{ id: "rec1" }], offset: "off1" }.to_json,
          headers: { "Content-Type" => "application/json" }
        ).then.to_return(
          status: 200,
          body:   { records: [{ id: "rec2" }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      records = client.list_records("Customers")
      expect(records.map { |r| r["id"] }).to eq %w[rec1 rec2]
    end

    it "raises RateLimitError on 429" do
      stub_request(:get, base_url).to_return(status: 429, body: "{}", headers: { "Content-Type" => "application/json" })
      expect { client.list_records("Customers") }
        .to raise_error(RailsAirtableSync::RateLimitError)
    end

    it "raises ApiError on 401" do
      stub_request(:get, base_url).to_return(status: 401, body: '{"error":"UNAUTHORIZED"}', headers: { "Content-Type" => "application/json" })
      expect { client.list_records("Customers") }
        .to raise_error(RailsAirtableSync::ApiError) { |e| expect(e.status).to eq 401 }
    end

    it "raises TransportError on network timeout" do
      stub_request(:get, base_url).to_timeout
      expect { client.list_records("Customers") }
        .to raise_error(RailsAirtableSync::TransportError)
    end
  end

  describe "#create_record" do
    it "posts and returns the created record" do
      stub_request(:post, base_url)
        .to_return(
          status: 200,
          body:   { id: "recNEW", fields: { "Email" => "new@test.com" } }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      record = client.create_record("Customers", { "Email" => "new@test.com" })
      expect(record["id"]).to eq "recNEW"
    end
  end

  describe "#update_record" do
    it "patches and returns the updated record" do
      stub_request(:patch, "#{base_url}/recABC")
        .to_return(
          status: 200,
          body:   { id: "recABC", fields: { "Email" => "updated@test.com" } }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      record = client.update_record("Customers", "recABC", { "Email" => "updated@test.com" })
      expect(record["id"]).to eq "recABC"
    end
  end
end
