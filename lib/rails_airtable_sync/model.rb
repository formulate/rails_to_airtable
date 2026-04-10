require "active_support/concern"

module RailsAirtableSync
  # Include this concern in any ActiveRecord model you want to sync to Airtable.
  #
  #   class Customer < ApplicationRecord
  #     include RailsAirtableSync::Model
  #
  #     airtable_sync table: "Customers" do
  #       scope { where(active: true) }
  #       record_key :id
  #       external_id_field "Rails ID"
  #
  #       field "Rails ID", from: :id, type: :integer, nullable: false
  #       field "Email",    from: :email, type: :email, nullable: false
  #
  #       checksum_fields :email, :created_at
  #     end
  #   end
  #
  module Model
    extend ActiveSupport::Concern

    included do
      # Expose the class-level ModelConfig after the block runs.
      class_attribute :airtable_sync_config, instance_writer: false
    end

    class_methods do
      # Entry point for the DSL.  Called once at class load time.
      def airtable_sync(table:, &block)
        config = ModelConfig.new(self, table)
        config.instance_eval(&block) if block
        config.validate!

        self.airtable_sync_config = config

        # Register this model with the gem registry so sync_all can find it.
        RailsAirtableSync.register_model(self)

        # Wire up after_commit callback if requested.
        if config.on_commit
          after_commit { RailsAirtableSync.enqueue_sync(self.class, record: self) }
        end
      end
    end

    # Instance convenience
    def sync_to_airtable!
      RailsAirtableSync.sync(self.class, record: self)
    end
  end
end
