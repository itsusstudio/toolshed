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
  skip_nil
end

module Caches
  class ProjectSummary < Studio::Cache
  end
end

Actor = Struct.new(:flipper_id)
Record = Struct.new(:cache_key_with_version)
