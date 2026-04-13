module RailsAirtableSync
  class Railtie < Rails::Railtie
    railtie_name :rails_airtable_sync

    # Load rake tasks
    rake_tasks do
      load File.expand_path("../tasks/airtable.rake", __dir__)
    end

    # Expose gem migration path so `bin/rails db:migrate` finds it
    initializer "rails_airtable_sync.migrations" do |app|
      migrations_path = File.expand_path("../../db/migrate", __dir__)
      if app.root.to_s != File.expand_path("../..", __dir__)
        app.config.paths["db/migrate"] << migrations_path
      end
    end

    # Validate configuration on app boot (fail fast for auth misconfig)
    initializer "rails_airtable_sync.validate_configuration", after: :load_config_initializers do
      RailsAirtableSync.configuration.validate! if RailsAirtableSync.configured?
    rescue ConfigurationError => e
      Rails.logger.error("[RailsAirtableSync] Configuration error: #{e.message}")
      raise
    end
  end
end
