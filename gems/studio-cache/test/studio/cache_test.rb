require "test_helper"

class Studio::CacheTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  def setup
    Rails.cache.clear
    Flipper.instance.features.each(&:remove)
    Studio::Cache.clear_all_process_stores
  end

  def teardown
    travel_back
  end

  def test_fetch_runs_the_block_once_and_serves_the_cached_value
    calls = 0
    2.times { BookmarkDetailsCache.fetch("https://a.test") { calls += 1 } }

    assert_equal 1, calls
    assert_equal 1, Rails.cache.read(BookmarkDetailsCache.key("https://a.test"))
  end

  def test_entries_expire_after_expires_in
    BookmarkDetailsCache.fetch("x") { "old" }
    travel 1.day + 1.second

    assert_equal "new", BookmarkDetailsCache.fetch("x") { "new" }
  end

  def test_never_cache_nil_keeps_failures_out
    ChangelogFeedCache.fetch("feed") { nil }

    assert_equal ["items"], ChangelogFeedCache.fetch("feed") { ["items"] }
  end

  def test_nil_is_cached_by_default
    BookmarkDetailsCache.fetch("x") { nil }

    assert_nil BookmarkDetailsCache.fetch("x") { "value" }
  end

  def test_delete_clears_the_entry
    BookmarkDetailsCache.fetch("x") { "old" }
    BookmarkDetailsCache.delete("x")

    assert_equal "new", BookmarkDetailsCache.fetch("x") { "new" }
  end

  def test_key_is_name_version_and_parts
    assert_equal "bookmark_details_cache/v1/https://a.test", BookmarkDetailsCache.key("https://a.test")
    assert_equal "changelog_feed_cache/v2/feed", ChangelogFeedCache.key("feed")
    assert_equal "caches/project_summary/v1/7", Caches::ProjectSummary.key(7)
  end

  def test_records_in_the_key_carry_their_version
    before = Record.new("projects/7-20261107")
    after = Record.new("projects/7-20261108")

    assert_equal "caches/project_summary/v1/projects/7-20261107", Caches::ProjectSummary.key(before)
    refute_equal Caches::ProjectSummary.key(before), Caches::ProjectSummary.key(after)
  end

  def test_different_parts_make_different_keys
    refute_equal BookmarkDetailsCache.key("a"), BookmarkDetailsCache.key("b")
  end

  def test_killswitch_is_named_after_the_class
    assert_equal "killswitch_bookmark_details_cache", BookmarkDetailsCache.killswitch
    assert_equal "killswitch_caches_project_summary", Caches::ProjectSummary.killswitch
  end

  def test_killed_runs_the_block_every_time_and_stores_nothing
    Flipper.enable(BookmarkDetailsCache.killswitch)
    calls = 0
    2.times { BookmarkDetailsCache.fetch("x") { calls += 1 } }

    assert_equal 2, calls
    assert_nil Rails.cache.read(BookmarkDetailsCache.key("x"))
    assert BookmarkDetailsCache.killed?
  end

  def test_killswitch_can_target_one_actor
    killed = Actor.new("Space;1")
    Flipper.enable_actor(BookmarkDetailsCache.killswitch, killed)

    assert BookmarkDetailsCache.killed?(actor: killed)
    refute BookmarkDetailsCache.killed?(actor: Actor.new("Space;2"))
    refute BookmarkDetailsCache.killed?
  end

  def test_settings_belong_to_each_cache
    assert_equal 1.day, BookmarkDetailsCache.ttl
    assert_equal 10.minutes, ChangelogFeedCache.ttl
    assert_nil Caches::ProjectSummary.ttl
    assert BookmarkDetailsCache.caches_nil
    refute ChangelogFeedCache.caches_nil
  end

  def test_rails_cache_is_the_default_store
    assert_equal :rails_cache, BookmarkDetailsCache.store_kind
  end

  def test_store_rejects_an_unknown_kind
    assert_raises(ArgumentError) { Class.new(Studio::Cache) { store :redis } }
  end

  def test_store_rejects_a_size_for_rails_cache
    assert_raises(ArgumentError) { Class.new(Studio::Cache) { store :rails_cache, size: 1.megabyte } }
  end

  def test_store_rejects_process_expires_in_outside_the_layered_store
    assert_raises(ArgumentError) { Class.new(Studio::Cache) { store :process, process_expires_in: 1.minute } }
  end

  def test_process_stores_require_a_size
    assert_raises(ArgumentError) { Class.new(Studio::Cache) { store :process } }
    assert_raises(ArgumentError) { Class.new(Studio::Cache) { store :process_then_rails_cache } }
  end

  def test_process_store_keeps_its_size
    assert_equal 1.megabyte, ParsedNumberCache.process_store_size
  end

  def test_process_store_keeps_values_out_of_rails_cache
    ParsedNumberCache.fetch("+16045551234") { "parsed" }

    assert_nil Rails.cache.read(ParsedNumberCache.key("+16045551234"))
    assert_equal "parsed", ParsedNumberCache.fetch("+16045551234") { "again" }
  end

  def test_process_store_reads_return_a_copy
    ParsedNumberCache.fetch("x") { ["a"] }
    ParsedNumberCache.fetch("x") { nil } << "b"

    assert_equal ["a"], ParsedNumberCache.fetch("x") { nil }
  end

  def test_process_store_entries_expire_after_expires_in
    ParsedNumberCache.fetch("x") { "old" }
    travel 1.day + 1.second

    assert_equal "new", ParsedNumberCache.fetch("x") { "new" }
  end

  def test_process_store_delete_clears_the_entry
    ParsedNumberCache.fetch("x") { "old" }
    ParsedNumberCache.delete("x")

    assert_equal "new", ParsedNumberCache.fetch("x") { "new" }
  end

  def test_each_cache_has_its_own_process_store
    ParsedNumberCache.fetch("x") { "parsed" }

    assert_equal "summary", FeedSummaryCache.fetch("x") { "summary" }
  end

  def test_clear_process_store_empties_only_that_cache
    ParsedNumberCache.fetch("x") { "parsed" }
    FeedSummaryCache.fetch("x") { "summary" }
    ParsedNumberCache.clear_process_store

    assert_equal "again", ParsedNumberCache.fetch("x") { "again" }
    assert_equal "summary", FeedSummaryCache.fetch("x") { "unused" }
  end

  def test_clear_all_process_stores_empties_every_cache
    ParsedNumberCache.fetch("x") { "parsed" }
    FeedSummaryCache.fetch("x") { "summary" }
    Rails.cache.clear
    Studio::Cache.clear_all_process_stores

    assert_equal "again", ParsedNumberCache.fetch("x") { "again" }
    assert_equal "again", FeedSummaryCache.fetch("x") { "again" }
  end

  def test_layered_store_serves_memory_before_rails_cache
    FeedSummaryCache.fetch("feed") { "first" }
    Rails.cache.write(FeedSummaryCache.key("feed"), "changed elsewhere")

    assert_equal "first", FeedSummaryCache.fetch("feed") { "unused" }
  end

  def test_layered_store_falls_back_to_rails_cache_after_process_expiry
    FeedSummaryCache.fetch("feed") { "first" }
    Rails.cache.write(FeedSummaryCache.key("feed"), "changed elsewhere", expires_in: 10.minutes)
    travel 1.minute + 1.second

    assert_equal "changed elsewhere", FeedSummaryCache.fetch("feed") { "unused" }
  end

  def test_layered_store_delete_clears_both_layers
    FeedSummaryCache.fetch("feed") { "old" }
    FeedSummaryCache.delete("feed")

    assert_nil Rails.cache.read(FeedSummaryCache.key("feed"))
    assert_equal "new", FeedSummaryCache.fetch("feed") { "new" }
  end

  def test_process_store_ignores_its_killswitch
    Flipper.enable(ParsedNumberCache.killswitch)
    calls = 0
    2.times { ParsedNumberCache.fetch("x") { calls += 1 } }

    refute ParsedNumberCache.killable?
    assert_equal 1, calls
  end

  def test_killed_layered_store_runs_the_block_every_time
    Flipper.enable(FeedSummaryCache.killswitch)
    calls = 0
    2.times { FeedSummaryCache.fetch("feed") { calls += 1 } }

    assert_equal 2, calls
    assert_nil Rails.cache.read(FeedSummaryCache.key("feed"))
  end
end
