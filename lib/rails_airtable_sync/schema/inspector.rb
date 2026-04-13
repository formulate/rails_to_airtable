module RailsAirtableSync
  module Schema
    # Fetches and caches the remote Airtable base schema (list of tables and
    # their fields) and provides lookup helpers.
    class Inspector
      # Lightweight struct for a remote field.
      RemoteField = Struct.new(:id, :name, :type, :options, keyword_init: true)

      # Lightweight struct for a remote table.
      RemoteTable = Struct.new(:id, :name, :fields, keyword_init: true) do
        def field_by_name(name)
          fields.find { |f| f.name == name }
        end
      end

      def initialize(client)
        @client = client
        @tables = nil
      end

      # Returns an array of RemoteTable structs for the entire base.
      # Result is memoised per Inspector instance; call #reload! to refresh.
      def tables
        @tables ||= fetch_tables
      end

      def reload!
        @tables = nil
        tables
        self
      end

      # Find a RemoteTable by name (case-sensitive).
      def find_table(name)
        tables.find { |t| t.name == name }
      end

      private

      def fetch_tables
        raw = @client.list_tables
        raw.map do |t|
          fields = Array(t["fields"]).map do |f|
            RemoteField.new(
              id:      f["id"],
              name:    f["name"],
              type:    f["type"],
              options: f["options"] || {}
            )
          end
          RemoteTable.new(id: t["id"], name: t["name"], fields: fields)
        end
      rescue TransportError, ApiError => e
        raise SchemaError, "Failed to fetch Airtable schema: #{e.message}"
      end
    end
  end
end
