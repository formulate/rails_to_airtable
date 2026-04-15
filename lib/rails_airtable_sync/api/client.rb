require "faraday"
require "faraday/retry"
require "json"

module RailsAirtableSync
  module Api
    # Low-level Airtable API client built on Faraday.
    #
    # Handles:
    #   - authentication (Bearer token)
    #   - JSON encoding/decoding
    #   - timeout configuration
    #   - error classification and raising
    #   - rate-limit detection (429 → RateLimitError)
    #
    # The retry layer is handled externally by RailsAirtableSync::Retry::Policy
    # so that we have full control over backoff jitter and state tracking.
    class Client
      RECORDS_BASE = "https://api.airtable.com/v0"
      META_BASE    = "https://api.airtable.com/v0/meta"

      def initialize(config)
        @config  = config
        @base_id = config.base_id
      end

      # ─── Records API ─────────────────────────────────────────────────────

      # List records, optionally filtering by formula.
      # Returns an array of record hashes.
      def list_records(table_name, filter_formula: nil, page_size: 100)
        params = { pageSize: page_size }
        params[:filterByFormula] = filter_formula if filter_formula

        records = []
        offset  = nil

        loop do
          params[:offset] = offset if offset
          resp = get(records_url(table_name), params: params)
          records.concat(resp.records)
          offset = resp.body["offset"]
          break unless offset
        end

        records
      end

      # Create a single record.  Returns the created record hash.
      def create_record(table_name, fields)
        resp = post(records_url(table_name), body: { fields: fields })
        resp.single_record
      end

      # Update (PATCH) fields on an existing record.  Returns the updated record hash.
      def update_record(table_name, record_id, fields)
        resp = patch("#{records_url(table_name)}/#{record_id}", body: { fields: fields })
        resp.single_record
      end

      # Delete a record.
      def delete_record(table_name, record_id)
        delete_req("#{records_url(table_name)}/#{record_id}")
      end

      # ─── Metadata API ────────────────────────────────────────────────────

      # Returns the full schema for the base (array of table hashes).
      def list_tables
        resp = get("#{META_BASE}/bases/#{@base_id}/tables")
        resp.tables
      end

      # Create a new table in the base.
      def create_table(name, fields: [])
        body = { name: name }
        body[:fields] = fields unless fields.empty?
        resp = post("#{META_BASE}/bases/#{@base_id}/tables", body: body)
        resp.body
      end

      # Create a new field on an existing table (by table ID).
      def create_field(table_id, field_definition)
        resp = post("#{META_BASE}/bases/#{@base_id}/tables/#{table_id}/fields",
                    body: field_definition)
        resp.body
      end

      # Update an existing field definition (by table ID and field ID).
      def update_field(table_id, field_id, updates)
        resp = patch("#{META_BASE}/bases/#{@base_id}/tables/#{table_id}/fields/#{field_id}",
                     body: updates)
        resp.body
      end

      private

      def get(url, params: {})
        execute(:get, url, params: params)
      end

      def post(url, body: {})
        execute(:post, url, body: body)
      end

      def patch(url, body: {})
        execute(:patch, url, body: body)
      end

      def delete_req(url)
        execute(:delete, url)
      end

      def execute(method, url, params: {}, body: nil)
        response = connection.public_send(method, url) do |req|
          req.params.merge!(params) unless params.empty?
          if body
            req.headers["Content-Type"] = "application/json"
            req.body = JSON.generate(body)
          end
        end

        api_response = Response.new(response)
        raise_on_error!(api_response, method: method, url: url)
        api_response
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        raise TransportError, "Network error calling Airtable [#{method.upcase} #{url}]: #{e.message}"
      end

      def raise_on_error!(resp, method:, url:)
        return if resp.success?

        if resp.rate_limit?
          raise RateLimitError.new(body: resp.body)
        end

        raise ApiError.new(
          "Airtable API error #{resp.status} [#{method.upcase} #{url}]: #{resp.body.inspect}",
          status: resp.status,
          body:   resp.body
        )
      end

      def connection
        @connection ||= Faraday.new do |f|
          f.options.timeout      = @config.timeout
          f.options.open_timeout = @config.open_timeout
          f.headers["Authorization"] = "Bearer #{@config.api_key}"
          f.headers["Accept"]        = "application/json"
          f.response :json, content_type: /\bjson$/
          f.adapter Faraday.default_adapter
        end
      end

      def records_url(table_name)
        # Use percent-encoding for path segments (spaces as %20, not +)
        encoded_name = URI.encode_www_form_component(table_name).gsub("+", "%20")
        "#{RECORDS_BASE}/#{@base_id}/#{encoded_name}"
      end
    end
  end
end
