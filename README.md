# toolshed

ITSUSSTUDIO's shared Ruby gems, one directory per gem under `gems/`, all prefixed `studio-`.

| Gem | What it is |
| --- | --- |
| [studio-monitoring](gems/studio-monitoring) | Logging, errors, metrics and analytics over AppSignal, PostHog and OpenTelemetry |

## Using a gem

All gems share one version (`VERSION`) and one release tag. Pin to a tag, never `main`:

```ruby
git "https://github.com/itsusstudio/toolshed", tag: "v0.1.0", glob: "gems/*/*.gemspec" do
  gem "studio-monitoring"
end
```

`glob:` is required: Bundler's default only finds gemspecs two levels deep.

To develop against a local checkout, override by gem name (one gem overrides the whole source):

```sh
bundle config local.studio-monitoring ~/projects/itsusstudio/toolshed
bundle config disable_local_branch_check true
```

Bundler refuses a local override on a `tag:` source without the second line.

## Working here

```sh
mise trust && mise install
bundle install
lefthook install
```

- `bin/ci [gem ...]` runs lint, a gem audit and the tests (every gem when none are named)
- `bin/lint`, `bin/style` check and fix style
- `bin/release 0.2.0` tags and pushes a release once `VERSION` says `0.2.0` on main

The lefthook pre-push hook runs `bin/ci` on pushes to main for the gems that changed. A change to a shared root file (Gemfile, lockfile, Ruby, VERSION, CI scripts) runs every gem.

## Adding a gem

Create `gems/studio-<name>/` with a `studio-<name>.gemspec` that reads its version from the root `VERSION`, and a `Rakefile` with a `test` task.
