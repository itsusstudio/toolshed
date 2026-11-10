---
name: add-toolshed-gem
description: Cut a new studio-* gem in toolshed, following the studio-monitoring layout and conventions
---

### When to use

When adding a gem to toolshed, or extracting code that two or more studio apps copy into a gem.

### Before starting

- Confirm with the user which code moves in and which apps will use it. Never extract without approval.
- Name it `studio-<name>`, with namespace `Studio::<Name>`. Never add a top-level constant.
- Read `gems/studio-monitoring` as the reference for a plain gem, and `gems/studio-auth` for an engine.

### Layout

```
gems/studio-<name>/
  studio-<name>.gemspec
  Rakefile
  README.md
  lib/studio/<name>.rb          # requires, configure, config
  lib/studio/<name>/...         # one file per class or module
  lib/studio/<name>/railtie.rb  # only if it hooks into Rails; engine.rb for an engine
  app/...                       # engine only: models, controllers, mailers, jobs, views
  config/locales/*.yml          # engine only
  test/test_helper.rb
  test/studio/<name>/..._test.rb
```

### Railtie or engine

- A plain gem with a `Railtie` for Ruby helpers, config, middleware, modules apps include, and boot checks. Its code lives in `lib/`, loads once and never reloads.
- A `Rails::Engine` as soon as the gem ships anything from a Rails `app/` folder: models, controllers, mailers, jobs, views, or translations. Rails autoloads and reloads the engine's `app/` with the app, finds its views, and loads its `config/locales` before the app's, so the app's own strings win.
- Code loaded once must never hold a reloadable class. A `belongs_to :user` on a model in `lib/` keeps the `User` from boot and rejects it after a development reload; the same model in the engine's `app/models` just works.
- `lib/` code may refer to reloadable classes by name inside methods, since it looks them up on each call.
- Mount and `isolate_namespace` only when the engine is its own mini-app under a path. studio-auth is not mounted: its routes sit at the app's root and its controllers inherit the app's `ApplicationController`.

- The gemspec reads its version from the root `VERSION` (copy studio-monitoring's line). Set `spec.files = Dir["lib/**/*.rb", "lib/**/*.tt", "README.md"]`, adding `"app/**/*"` and `"config/locales/*.yml"` for an engine.
- Give dependencies loose bounds (`~> 0.8`, `>= 8.0`). Apps pin exact versions in their lockfiles.
- Copy the `Rakefile` from studio-monitoring unchanged.
- The root `Gemfile` picks up the new gemspec automatically. Run `bundle install` at the root so `Gemfile.lock` updates.

### Conventions

- Build on what Rails ships (`Rails.event`, `Rails.error`, `Rails.logger`, `CurrentAttributes`, `filter_parameters`, `ActiveSupport::Notifications`) before writing any API of your own. Apps call a thin `Studio::<Name>::<Module>` interface over the Rails primitive, like `Studio::Monitoring::Events` over `Rails.event`.
- Fix studio conventions in code. Add a config setting only for something that differs between apps today. Remove settings that nothing uses.
- Configure through `Studio::<Name>.configure do |c| ... end`, called in an app initializer. Required settings raise at boot from a `validate_config!` called by the Railtie or engine.
- The gem owns any pluggable parts, and apps pick them by symbol from a registry the gem ships. Never accept app classes.
- Load Active Record and Active Job classes with `autoload`, so requiring the gem doesn't load those frameworks early.
- Comments only for a non-obvious why or a trap. No narration.

### Tests

- Minitest + mocha, run against a small Rails app in `test/test_helper.rb` (see studio-monitoring). Use in-memory sqlite through `DATABASE_URL` if the gem needs a database.
- Port the apps' existing tests for the extracted code. Then add tests for the config and its boot-time validation.

### Wire up

- Add the gem to the list in the root `README.md`.
- The pre-push hook finds every gem in `gems/` on its own, so it needs no change.
- Run `bin/ci <gem>`, then `bin/ci` to check every gem still passes together.
- Commit only with the user's approval, staging explicit paths. No AI attribution.

### Releasing

Apps track `main` (`branch: "main"`) and pin a commit in `Gemfile.lock`, so a release is a push to main. Apps add the gem to their existing toolshed `git` block and run `bundle update <gem>`.
