require "rails"
require "active_support/core_ext/class/attribute"
require "flipper"

module Studio
  # One subclass per cache, in app/caches:
  #
  #   class BookmarkDetailsCache < Studio::Cache
  #     expires_in 1.day
  #     version 1
  #   end
  #
  #   BookmarkDetailsCache.fetch(url) { read_details(url) }
  class Cache
    class_attribute :ttl, instance_accessor: false, default: nil
    class_attribute :cache_version, instance_accessor: false, default: 1
    class_attribute :nil_skipped, instance_accessor: false, default: false

    class << self
      def expires_in(duration)
        self.ttl = duration
      end

      # Bump when the key's inputs or the cached value's shape change.
      def version(number)
        self.cache_version = number
      end

      # Keeps nil out, so a failed lookup runs again on the next call
      # instead of being served until it expires.
      def skip_nil
        self.nil_skipped = true
      end

      def fetch(*parts, actor: nil, &block)
        return yield if killed?(actor: actor)

        ::Rails.cache.fetch(key(*parts), expires_in: ttl, skip_nil: nil_skipped, &block)
      end

      def delete(*parts)
        ::Rails.cache.delete(key(*parts))
      end

      # Records expand to cache_key_with_version, so an update makes a new key.
      def key(*parts)
        ActiveSupport::Cache.expand_cache_key([name.underscore, "v#{cache_version}", *parts])
      end

      # On kills the cache: fetch runs the block uncached. Off, the default,
      # caches, so a new cache works as soon as it deploys.
      def killswitch
        "killswitch_#{name.underscore.tr("/", "_")}"
      end

      def killed?(actor: nil)
        Flipper.enabled?(killswitch, actor)
      end
    end
  end
end
