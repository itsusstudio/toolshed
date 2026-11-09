require "rails"
require "active_support/core_ext/class/attribute"
require "active_support/core_ext/class/subclasses"
require "active_support/core_ext/numeric/bytes"
require "active_support/core_ext/numeric/time"
require "monitor"
require "flipper"

module Studio
  class Cache
    STORES = [:rails_cache, :process, :process_then_rails_cache].freeze
    PROCESS_STORE_LOCK = Monitor.new

    class_attribute :ttl, instance_accessor: false, default: nil
    class_attribute :cache_version, instance_accessor: false, default: 1
    class_attribute :caches_nil, instance_accessor: false, default: true
    class_attribute :store_kind, instance_accessor: false, default: :rails_cache
    class_attribute :process_store_size, instance_accessor: false, default: nil
    class_attribute :process_ttl, instance_accessor: false, default: nil

    class << self
      def expires_in(duration)
        self.ttl = duration
      end

      def version(number)
        self.cache_version = number
      end

      # A cached nil would be served until it expires instead of the failed
      # lookup running again on the next call.
      def never_cache_nil
        self.caches_nil = false
      end

      # Where the cache lives:
      #
      #   class ParsedPhoneNumberCache < Studio::Cache
      #     store :process, size: 2.megabytes
      #   end
      #
      #   store :rails_cache                    # the default
      #   store :process, size: 2.megabytes     # memory in each process
      #   store :process_then_rails_cache, size: 4.megabytes, process_expires_in: 1.minute
      def store(kind, size: nil, process_expires_in: nil)
        if !STORES.include?(kind)
          raise ArgumentError, "unknown store #{kind.inspect}, expected one of #{STORES.inspect}"
        end
        if size && kind == :rails_cache
          raise ArgumentError, "size: only applies to stores that keep values in process memory"
        end
        # Each process store holds memory in every web and job process, so its
        # budget is chosen per cache rather than defaulted.
        if !size && kind != :rails_cache
          raise ArgumentError, "size: is required for #{kind.inspect} stores"
        end
        if process_expires_in && kind != :process_then_rails_cache
          raise ArgumentError, "process_expires_in: only applies to :process_then_rails_cache"
        end

        self.store_kind = kind
        self.process_store_size = size
        self.process_ttl = process_expires_in
      end

      def fetch(*key_inputs, actor: nil, &block)
        return yield if killable? && killed?(actor: actor)

        key = key(*key_inputs)
        case store_kind
        when :rails_cache
          rails_cache_store.fetch(key, **fetch_options, &block)
        when :process
          process_store.fetch(key, **fetch_options, &block)
        when :process_then_rails_cache
          process_store.fetch(key, **fetch_options(expires_in: process_ttl || ttl)) do
            rails_cache_store.fetch(key, **fetch_options, &block)
          end
        end
      end

      # A process store only clears the process this runs in; other processes
      # keep their copy until it expires.
      def delete(*key_inputs)
        key = key(*key_inputs)
        process_store.delete(key) if uses_process_store?
        rails_cache_store.delete(key) if uses_rails_cache?
      end

      # Records expand to cache_key_with_version, so an update makes a new key.
      def key(*key_inputs)
        ActiveSupport::Cache.expand_cache_key([name.underscore, "v#{cache_version}", *key_inputs])
      end

      def uses_process_store?
        store_kind != :rails_cache
      end

      def uses_rails_cache?
        store_kind != :process
      end

      # Only data in Rails.cache can go stale. A process store holds results
      # that depend on nothing but their inputs and empties on deploy, so a
      # killswitch would only add a Flipper lookup to every read.
      def killable?
        uses_rails_cache?
      end

      # A killswitch, not an enable flag, so a new cache works as soon as it
      # deploys.
      def killswitch
        "killswitch_#{name.underscore.tr("/", "_")}"
      end

      def killed?(actor: nil)
        Flipper.enabled?(killswitch, actor)
      end

      # Empties this cache's memory store in the current process, for tests and
      # consoles. Rails.cache entries are left alone.
      def clear_process_store
        @process_store&.clear
      end

      # Empties every loaded cache's memory store; call it in test setup so
      # entries don't leak between tests.
      def clear_all_process_stores
        descendants.each(&:clear_process_store)
      end

      private

      def process_store
        @process_store || PROCESS_STORE_LOCK.synchronize do
          @process_store ||= ActiveSupport::Cache::MemoryStore.new(size: process_store_size)
        end
      end

      def rails_cache_store
        ::Rails.cache
      end

      def fetch_options(expires_in: ttl)
        {expires_in: expires_in, skip_nil: !caches_nil}
      end
    end
  end
end
