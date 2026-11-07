# studio-settings

`config/app.yml` as `AppSettings`: nested, immutable, dot-accessible, and a mistyped or missing key raises `NoMethodError` instead of returning nil.

```yaml
# config/app.yml; config_for deep-merges shared into the current environment
shared:
  product:
    name: "Belly"
production:
  application:
    app_host: "my.usebelly.app"
```

```ruby
# config/application.rb, inside the Application class
config.x.app = Studio::Settings.build(config_for(:app))
```

```ruby
# after the class, so config/environments and the app can read it
AppSettings = Rails.application.config.x.app

AppSettings.product.name             # "Belly"
AppSettings.application.app_host
```

Add `gem "studio-settings"` to the toolshed block. App-wide constants (names, URLs, hosts, per-environment endpoints) go in app.yml; secrets go in credentials.

To test another environment's values, `Studio::Settings.for_env("production")` loads them.
