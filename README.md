# toolshed

Studio Ruby gems, one per directory in `gems/`.

- [studio-app-bintools](gems/studio-app-bintools)
- [studio-cache](gems/studio-cache)
- [studio-enum](gems/studio-enum)
- [studio-flags](gems/studio-flags)
- [studio-monitoring](gems/studio-monitoring)
- [studio-rack-attack](gems/studio-rack-attack)
- [studio-settings](gems/studio-settings)
- [studio-site-bintools](gems/studio-site-bintools)
- [studio-standardrb](gems/studio-standardrb)

## Install

```ruby
git "https://github.com/itsusstudio/toolshed", branch: "main", glob: "gems/*/*.gemspec" do
  gem "studio-monitoring"
end
```

`Gemfile.lock` pins the commit. Take new toolshed code with `bundle update studio-monitoring`.

Local checkout:

```sh
bundle config local.studio-monitoring ~/projects/itsusstudio/toolshed
```

## Develop

```sh
mise install && bundle install && lefthook install
bin/ci [gem ...]
```

Apps track `main`, so keep it green: pushing to main runs `bin/ci` for the gems that changed.
