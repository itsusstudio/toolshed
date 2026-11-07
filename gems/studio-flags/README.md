# studio-flags

Feature flags for studio Rails apps. `config/feature_flags.yml` lists every flag; Flipper owns whether each one is on.

```yaml
# config/feature_flags.yml
feature_enable_bella:
  description: "On: Bella answers in the party sheet. Off: the entry is hidden."
killswitch_bookmark_details_cache:
  description: "On: bookmark details are fetched every time. Off: cached."
```

```ruby
Flipper.enabled?("feature_enable_bella", current_user)
```

1. Add the flag to the file with a description.
2. Deploy. `bin/rails flipper:sync` adds it, off everywhere.
3. Turn it on in the Flipper UI.
4. Once rolled out, delete it from the file and the code; the next sync removes it.

Name rollouts `feature_enable_<name>` and cache killswitches as [studio-cache](../studio-cache) names them. Say what happens in each state, tersely.

## Setup

Add `gem "studio-flags"` to the toolshed block in the Gemfile, next to `flipper`, `flipper-ui` and `flipper-active_record`. Then:

- `flipper:sync` runs from `bin/studio release` when `STUDIO_FLIPPER` is set, and should run in `bin/setup`. On Postgres an advisory lock lets instances booting together skip it.
- The Flipper UI shows each flag's description, can't create or remove flags, and has an environment banner. Mount it yourself.

```ruby
# test/test_helper.rb
require "studio/flags/test_helper"

class ActiveSupport::TestCase
  include Studio::Flags::TestHelper  # every flag exists, off, so strict mode allows checking it
end
```

`Studio::Flags.names` and `Studio::Flags.descriptions` read the file.
