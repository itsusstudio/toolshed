require "test_helper"

class Studio::CacheTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  def setup
    Rails.cache.clear
    Flipper.instance.features.each(&:remove)
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

  def test_skip_nil_keeps_failures_out
    ChangelogFeedCache.fetch("feed") { nil }

    assert_equal ["items"], ChangelogFeedCache.fetch("feed") { ["items"] }
  end

  def test_without_skip_nil_nil_is_cached
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
    refute BookmarkDetailsCache.nil_skipped
    assert ChangelogFeedCache.nil_skipped
  end
end
