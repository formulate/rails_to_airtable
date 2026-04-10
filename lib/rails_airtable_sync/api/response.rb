module RailsAirtableSync
  module Api
    # Thin wrapper around a Faraday response that normalises status/body access
    # and exposes helper predicates.
    class Response
      attr_reader :status, :body, :headers

      def initialize(faraday_response)
        @status  = faraday_response.status
        @headers = faraday_response.headers
        @body    = parse_body(faraday_response.body)
      end

      def success?    = (200..299).cover?(status)
      def rate_limit? = status == 429
      def server_error? = status >= 500
      def client_error? = (400..499).cover?(status) && status != 429

      def records
        body.is_a?(Hash) ? Array(body["records"]) : []
      end

      def single_record
        body.is_a?(Hash) ? body : nil
      end

      def tables
        body.is_a?(Hash) ? Array(body["tables"]) : []
      end

      private

      def parse_body(raw)
        return raw if raw.is_a?(Hash) || raw.is_a?(Array)
        return {} if raw.nil? || raw.empty?

        JSON.parse(raw)
      rescue JSON::ParserError
        raw
      end
    end
  end
end
