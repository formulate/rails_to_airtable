require_relative "lib/rails_airtable_sync/version"

Gem::Specification.new do |spec|
  spec.name    = "rails_airtable_sync"
  spec.version = RailsAirtableSync::VERSION
  spec.authors = ["rails_airtable_sync contributors"]
  spec.summary = "One-way synchronization from Rails models to Airtable records"
  spec.description = <<~DESC
    rails_airtable_sync pushes Rails model data to Airtable reliably, with
    idempotent operations, schema auto-reconciliation, strict type enforcement,
    checksum-based change detection, retry/quarantine semantics, and structured
    instrumentation. Rails is always the source of truth.
  DESC
  spec.license  = "MIT"
  spec.homepage = "https://github.com/your-org/rails_airtable_sync"

  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir[
    "lib/**/*.rb",
    "lib/tasks/**/*.rake",
    "db/migrate/**/*.rb",
    "*.gemspec",
    "Gemfile",
    "LICENSE",
    "README.md"
  ]

  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport",   ">= 7.0"
  spec.add_dependency "activerecord",    ">= 7.0"
  spec.add_dependency "activejob",       ">= 7.0"
  spec.add_dependency "faraday",         "~> 2.0"
  spec.add_dependency "faraday-retry",   "~> 2.0"

  spec.add_development_dependency "rails",        ">= 7.0"
  spec.add_development_dependency "rspec-rails",  "~> 6.0"
  spec.add_development_dependency "webmock",      "~> 3.0"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "factory_bot_rails"
  spec.add_development_dependency "timecop"
end
