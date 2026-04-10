module RailsAirtableSync
  module Schema
    # Executes schema mutations against the Airtable Metadata API.
    # Wraps API errors into SchemaMutationError.
    class MutationExecutor
      def initialize(client:)
        @client = client
      end

      def create_table(name, fields: [])
        @client.create_table(name, fields: fields)
      rescue ApiError, TransportError => e
        raise SchemaMutationError, "Failed to create table '#{name}': #{e.message}"
      end

      def create_field(table_id, field_definition)
        @client.create_field(table_id, field_definition)
      rescue ApiError, TransportError => e
        raise SchemaMutationError,
              "Failed to create field '#{field_definition[:name]}' on table #{table_id}: #{e.message}"
      end

      def update_field(table_id, field_id, updates)
        @client.update_field(table_id, field_id, updates)
      rescue ApiError, TransportError => e
        raise SchemaMutationError,
              "Failed to update field #{field_id} on table #{table_id}: #{e.message}"
      end
    end
  end
end
