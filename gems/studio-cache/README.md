# studio-cache

One class per cache, in `Rails.cache` (the default), in each process's memory, or both. Caches that use `Rails.cache` sit behind a Flipper killswitch.

```ruby
# app/caches/bookmark_details_cache.rb
class BookmarkDetailsCache < Studio::Cache
  expires_in 1.day
  version 1          # bump when the key's inputs or the value's shape change
end

class ChangelogFeedCache < Studio::Cache
  expires_in 10.minutes
  never_cache_nil    # a failed lookup runs again next call
end
```

```ruby
BookmarkDetailsCache.fetch(url) { read_details(url) }
ProjectSummaryCache.fetch(project, actor: shop) { summarize(project) }
ProjectSummaryCache.delete(project)
```

## Stores

Cache only work that costs far more than a lookup.

| Store | Lookup costs | Wiped by | For |
| --- | --- | --- | --- |
| `:rails_cache` (default) | a round trip (a query on Solid Cache) | expiry, `delete`, a version bump | slow queries, outside APIs, LLM calls |
| `:process` | a hash lookup | expiry, a deploy, LRU past `size:` | results of their inputs alone: parsing, formatting, fixed data. No killswitch |
| `:process_then_rails_cache` | a hash lookup, a round trip on a miss | memory after `process_expires_in`, then as `:rails_cache` | expensive reads where a minute stale per process is fine |

```ruby
class ParsedPhoneNumberCache < Studio::Cache
  store :process, size: 2.megabytes   # size is required
  expires_in 1.day
end

class FeedSummaryCache < Studio::Cache
  store :process_then_rails_cache, size: 4.megabytes, process_expires_in: 1.minute
  expires_in 10.minutes
end
```

Process stores hand back a copy (values must be Marshal-able), and `delete` clears only the current process, so keep anything tied to records, settings or the clock in `:rails_cache`.

## Keys

The class name, the version and every input you pass. A record expands to `cache_key_with_version`, so an update makes a new key. Pass everything the value depends on, including tenant, locale and viewer, or it's served stale or to the wrong tenant.

```ruby
ProjectSummaryCache.key(project)    # => "project_summary_cache/v1/projects/42-20261107093000000000"
```

## Killswitch

Register the flag named after the class in `config/feature_flags.yml`. Off (the default), the cache works. On, `fetch` runs the block uncached; `actor:` kills it for one tenant.

```ruby
BookmarkDetailsCache.killswitch               # => "killswitch_bookmark_details_cache"
BookmarkDetailsCache.killed?(actor: shop)
```

## Tests and console

```ruby
setup { Studio::Cache.clear_all_process_stores }   # so memory entries don't leak between tests
Flipper.enable(BookmarkDetailsCache.killswitch)    # to test the uncached path
```

`XCache.clear_process_store` empties one cache's memory in the current process; `Rails.cache.clear` busts every shared entry.

## Setup

In the toolshed `git` block of the Gemfile: `gem "studio-cache"`. Needs Flipper.
