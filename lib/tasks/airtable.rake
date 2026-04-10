namespace :airtable do
  desc "Sync a Rails model to Airtable. Example: bin/rails airtable:sync[Customer]"
  task :sync, [:model_name] => :environment do |_t, args|
    model_name = args[:model_name]
    abort "Usage: bin/rails airtable:sync[ModelName]" if model_name.blank?

    model_class = model_name.constantize
    puts "Syncing #{model_name}..."
    results = RailsAirtableSync.engine.sync_model(model_class)
    summarize(results, model_name)
  end

  desc "Sync all registered Rails models to Airtable"
  task sync_all: :environment do
    RailsAirtableSync.registered_models.each do |model_class|
      puts "Syncing #{model_class.name}..."
      results = RailsAirtableSync.engine.sync_model(model_class)
      summarize(results, model_class.name)
    end
  end

  desc "Re-sync only failed or pending records for a model. Example: bin/rails airtable:resync_failed[Customer]"
  task :resync_failed, [:model_name] => :environment do |_t, args|
    model_name = args[:model_name]
    abort "Usage: bin/rails airtable:resync_failed[ModelName]" if model_name.blank?

    model_class = model_name.constantize
    puts "Re-syncing failed records for #{model_name}..."
    results = RailsAirtableSync.engine.sync_model(model_class, only_failed: true)
    summarize(results, model_name)
  end

  desc "Verify Airtable records match Rails without writing. Example: bin/rails airtable:verify[Customer]"
  task :verify, [:model_name] => :environment do |_t, args|
    model_name = args[:model_name]
    abort "Usage: bin/rails airtable:verify[ModelName]" if model_name.blank?

    puts "Verify mode not yet implemented — use airtable:sync with verify_after_write=true"
  end

  def summarize(results, model_name)
    synced  = results.count { |r| r.success? && !r.skipped? }
    skipped = results.count(&:skipped?)
    failed  = results.count(&:failed?)
    puts "#{model_name}: synced=#{synced} skipped=#{skipped} failed=#{failed}"
    if failed > 0
      puts "Failed record IDs: #{results.select(&:failed?).map(&:record_id).join(', ')}"
    end
  end
end
