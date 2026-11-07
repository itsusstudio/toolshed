namespace :flipper do
  desc "Make Flipper match config/feature_flags.yml: add new flags, off, and remove deleted ones"
  task sync: :environment do
    sync = Studio::Flags.sync!
    next puts("flipper:sync already running on another instance, skipping") if sync.skipped

    sync.added.each { puts "  + #{it}" }
    sync.removed.each { puts "  - #{it}" }
    puts "Flipper sync complete"
  end
end
