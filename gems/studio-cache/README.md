# studio-cache

One class per cache. A cache lives in `Rails.cache` (the default), in the memory of each process, or in both. Caches that touch `Rails.cache` sit behind a Flipper killswitch.

```ruby
# app/caches/bookmark_details_cache.rb
class BookmarkDetailsCache < Studio::Cache
  expires_in 1.day
  version 1          # bump when the key's inputs or the value's shape change
end

# app/caches/changelog_feed_cache.rb
class ChangelogFeedCache < Studio::Cache
  expires_in 10.minutes
  never_cache_nil    # a failed lookup runs again on the next call
end
```

```ruby
BookmarkDetailsCache.fetch(url) { read_details(url) }
ChangelogFeedCache.fetch(feed_url) { request_items(feed_url) } || []
ProjectSummaryCache.fetch(project, actor: shop) { summarize(project) }
ProjectSummaryCache.delete(project)
```

## Where it lives

A cache only pays off when a lookup costs much less than the work it replaces, so pick the store by what a lookup costs and what wipes it:

| Store | Lives in | Shared by | Wiped by | A lookup costs |
|---|---|---|---|---|
| `:rails_cache` (default) | `Rails.cache` | every process and server | expiry, `delete`, a version bump | a round trip to the cache backend (a Postgres query on Solid Cache) |
| `:process` | a `MemoryStore` in each process | one process | expiry, a deploy or restart, LRU eviction past `size:` | a hash lookup |
| `:process_then_rails_cache` | memory first, then `Rails.cache` | memory per process, `Rails.cache` everywhere | memory after `process_expires_in`, then as `:rails_cache` | a hash lookup, a round trip on a memory miss |

```ruby
# Cheap work repeated many times per request, whose result can't go stale.
class ParsedPhoneNumberCache < Studio::Cache
  store :process, size: 2.megabytes   # required: memory per process
  expires_in 1.day
end

# Expensive work read often, where a minute of staleness per process is fine.
class FeedSummaryCache < Studio::Cache
  store :process_then_rails_cache, size: 4.megabytes, process_expires_in: 1.minute
  expires_in 10.minutes
end
```

- `:rails_cache` is for work that costs far more than a round trip: slow queries, outside APIs, LLM calls. Values survive deploys and every process sees the same one.
- A process store hands back a copy of the stored value (Marshal, like any `MemoryStore`), so cached values must be serializable, and changing a value you read doesn't change the cache.
- `delete` on a process store clears only the process it runs in. Other processes keep their copy until it expires, so use process stores for values that can't go stale or that have a short expiry.
- `:process` is only for results that depend on nothing but their inputs: parsing, formatting, lookups in fixed data. It has no killswitch, because such a cache can't serve stale data and a deploy empties it. Anything tied to records, settings or the clock goes in `:rails_cache`.

## Keys

The key is the class name, the version and the key inputs you pass, built by Rails:

```ruby
BookmarkDetailsCache.key(url)       # => "bookmark_details_cache/v1/https://..."
ProjectSummaryCache.key(project)    # => "project_summary_cache/v1/projects/42-20261107093000000000"
```

A record expands to `cache_key_with_version`, so updating it makes a new key. Pass everything the value depends on: records, tenant, locale, filters, viewer. Anything left out is served stale, or to the wrong tenant.

## Killswitch

`:rails_cache` and `:process_then_rails_cache` caches read the flag named after their class. Register it in `config/feature_flags.yml`:

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

In test setup, empty every memory store so entries don't leak between tests:

```ruby
setup { Studio::Cache.clear_all_process_stores }
```

`XCache.clear_process_store` empties one cache's memory store in the current process (handy in a console).

To bust every `Rails.cache` entry at once: `Rails.cache.clear`. Process stores empty on the next deploy or restart.

## Setup

In the toolshed `git` block of the Gemfile: `gem "studio-cache"`. Needs Flipper.
