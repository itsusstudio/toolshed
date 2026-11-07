require "rails"
require "yaml"
require "flipper"

module Studio
  # config/feature_flags.yml lists every flag; Flipper owns whether each is on.
  # Flags are only ever created and removed through the file, so sync! makes
  # Flipper match it.
  module Flags
    REGISTRY = "config/feature_flags.yml"

    # Stable bigint key for pg_advisory_lock, so it can't collide with Rails'
    # migration lock or any other advisory lock in the app.
    SYNC_LOCK_KEY = 4_815_162_342

    Sync = Data.define(:added, :removed, :skipped)

    class << self
      def descriptions
        registry.to_h { |name, config| [name, config.is_a?(Hash) ? config["description"].to_s : ""] }
      end

      def names
        registry.keys
      end

      # Adds registered flags Flipper lacks, off, and removes the ones the
      # registry no longer lists. Safe to run from several instances booting
      # at once: on Postgres, all but one skip.
      def sync!
        with_sync_lock do
          Flipper::Adapters::Strict.with_sync_mode do
            added = (names - Flipper.features.map(&:key)).each { Flipper.add(it) }
            removed = Flipper.features.reject { names.include?(it.key) }.each(&:remove).map(&:key)
            Sync.new(added: added, removed: removed, skipped: false)
          end
        end
      end

      private

      def registry
        path = ::Rails.root.join(REGISTRY)
        (path.exist? && YAML.load_file(path)) || {}
      end

      def with_sync_lock
        return yield if !postgres?

        connection = ActiveRecord::Base.lease_connection
        return Sync.new(added: [], removed: [], skipped: true) if !connection.select_value("SELECT pg_try_advisory_lock(#{SYNC_LOCK_KEY})")

        begin
          yield
        ensure
          connection.execute("SELECT pg_advisory_unlock(#{SYNC_LOCK_KEY})")
        end
      end

      def postgres?
        defined?(ActiveRecord::Base) && ActiveRecord::Base.connection_db_config&.adapter.to_s.start_with?("postg")
      end
    end
  end
end

require_relative "flags/railtie" if defined?(Rails::Railtie)
