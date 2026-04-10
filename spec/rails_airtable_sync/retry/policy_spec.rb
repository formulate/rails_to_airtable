require "spec_helper"

RSpec.describe RailsAirtableSync::Retry::Policy do
  let(:config) do
    RailsAirtableSync.configuration.tap do |c|
      c.max_retries   = 3
      c.retry_backoff = :exponential
      c.retry_jitter  = false
    end
  end

  let(:policy) { described_class.new(config) }

  before { allow(policy).to receive(:sleep) }

  describe "#with_retry" do
    it "passes through the block result on success" do
      result = policy.with_retry { 42 }
      expect(result).to eq 42
    end

    it "retries on TransportError and succeeds" do
      calls = 0
      result = policy.with_retry do
        calls += 1
        raise RailsAirtableSync::TransportError, "timeout" if calls < 3
        "ok"
      end
      expect(result).to eq "ok"
      expect(calls).to eq 3
    end

    it "raises after max_retries exhausted" do
      expect {
        policy.with_retry { raise RailsAirtableSync::TransportError, "gone" }
      }.to raise_error(RailsAirtableSync::TransportError)
    end

    it "retries on 429 RateLimitError" do
      calls = 0
      expect {
        policy.with_retry do
          calls += 1
          raise RailsAirtableSync::RateLimitError
        end
      }.to raise_error(RailsAirtableSync::RateLimitError)
      expect(calls).to eq 4  # 1 initial + 3 retries
    end

    it "does not retry on non-retryable ApiError (401)" do
      calls = 0
      expect {
        policy.with_retry do
          calls += 1
          raise RailsAirtableSync::ApiError.new("unauthorized", status: 401)
        end
      }.to raise_error(RailsAirtableSync::ApiError)
      expect(calls).to eq 1
    end

    it "retries on 503 ApiError" do
      calls = 0
      expect {
        policy.with_retry do
          calls += 1
          raise RailsAirtableSync::ApiError.new("server error", status: 503)
        end
      }.to raise_error(RailsAirtableSync::ApiError)
      expect(calls).to eq 4
    end
  end

  describe "#retryable?" do
    it "returns true for TransportError" do
      expect(policy.retryable?(RailsAirtableSync::TransportError.new)).to be true
    end

    it "returns true for RateLimitError" do
      expect(policy.retryable?(RailsAirtableSync::RateLimitError.new)).to be true
    end

    it "returns true for retryable ApiError (5xx)" do
      err = RailsAirtableSync::ApiError.new("bad gateway", status: 502)
      expect(policy.retryable?(err)).to be true
    end

    it "returns false for non-retryable ApiError (422)" do
      err = RailsAirtableSync::ApiError.new("unprocessable", status: 422)
      expect(policy.retryable?(err)).to be false
    end

    it "returns false for ValidationError" do
      err = RailsAirtableSync::ValidationError.new("bad field")
      expect(policy.retryable?(err)).to be false
    end
  end
end
