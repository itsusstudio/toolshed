require "studio/cache"
require "active_support/core_ext/integer/time"
require "active_support/testing/time_helpers"
require "minitest/autorun"

Rails.cache = ActiveSupport::Cache::MemoryStore.new
Flipper.configure { |config| config.adapter { Flipper::Adapters::Memory.new } }

class BookmarkDetailsCache < Studio::Cache
  expires_in 1.day
end

class ChangelogFeedCache < Studio::Cache
  expires_in 10.minutes
  version 2
  never_cache_nil
end

module Caches
  class ProjectSummary < Studio::Cache
  end
end

class ParsedNumberCache < Studio::Cache
  store :process, size: 1.megabyte
  expires_in 1.day
end

class FeedSummaryCache < Studio::Cache
  store :process_then_rails_cache, size: 1.megabyte, process_expires_in: 1.minute
  expires_in 10.minutes
end

Actor = Struct.new(:flipper_id)
Record = Struct.new(:cache_key_with_version)
