# toolshed

Studio Ruby gems, one per directory in `gems/`.

- [studio-monitoring](gems/studio-monitoring)

## Install

```ruby
git "https://github.com/itsusstudio/toolshed", tag: "v0.1.0", glob: "gems/*/*.gemspec" do
  gem "studio-monitoring"
end
```

Local checkout:

```sh
bundle config local.studio-monitoring ~/projects/itsusstudio/toolshed
bundle config disable_local_branch_check true
```

## Develop

```sh
mise install && bundle install && lefthook install
bin/ci [gem ...]
bin/release 0.2.0
```

Pushing to main runs `bin/ci` for the gems that changed.
