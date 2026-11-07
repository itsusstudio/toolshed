# studio-cache

One class per cache over `Rails.cache`, each behind a Flipper killswitch.

```ruby
# app/caches/bookmark_details_cache.rb
class BookmarkDetailsCache < Studio::Cache
  expires_in 1.day
  version 1          # bump when the key's inputs or the value's shape change
end

# app/caches/changelog_feed_cache.rb
class ChangelogFeedCache < Studio::Cache
  expires_in 10.minutes
  skip_nil           # failures aren't cached, so the next call retries
end
```

```ruby
BookmarkDetailsCache.fetch(url) { read_details(url) }
ChangelogFeedCache.fetch(feed_url) { request_items(feed_url) } || []
ProjectSummaryCache.fetch(project, actor: shop) { summarize(project) }
ProjectSummaryCache.delete(project)
```

## Keys

The key is the class name, the version and the parts you pass, built by Rails:

```ruby
BookmarkDetailsCache.key(url)       # => "bookmark_details_cache/v1/https://..."
ProjectSummaryCache.key(project)    # => "project_summary_cache/v1/projects/42-20261107093000000000"
```

A record expands to `cache_key_with_version`, so updating it makes a new key. Pass everything the value depends on: records, tenant, locale, filters, viewer. Anything left out is served stale, or to the wrong tenant.

## Killswitch

Each cache reads the flag named after its class. Register it in `config/feature_flags.yml`:

```ruby
BookmarkDetailsCache.killswitch          # => "killswitch_bookmark_details_cache"
BookmarkDetailsCache.killed?(actor: shop)
```

Off, the default, caches, so a new cache works as soon as it deploys. On, `fetch` runs the block uncached. `actor:` kills it for one tenant.

## Tests

```ruby
test "different urls get different keys" do
  refute_equal BookmarkDetailsCache.key("a"), BookmarkDetailsCache.key("b")
end

test "killed, the block runs every time" do
  Flipper.enable(BookmarkDetailsCache.killswitch)
  # ...
end
```

To bust every cache at once: `Rails.cache.clear`.

## Setup

In the toolshed `git` block of the Gemfile: `gem "studio-cache"`. Needs Flipper.
