ENV["RAILS_ENV"] = "test"

require "rails"
require "studio/settings"
require "minitest/autorun"

# test/dummy is gitignored, so app.yml is written at boot.
FileUtils.mkdir_p(File.expand_path("dummy/config", __dir__))
File.write(File.expand_path("dummy/config/app.yml", __dir__), <<~YAML)
  shared:
    product:
      name: "Belly"
  test:
    application:
      app_host: "belly.localhost"
  production:
    application:
      app_host: "my.usebelly.app"
YAML

class DummyApp < Rails::Application
  config.root = File.expand_path("dummy", __dir__)
  config.eager_load = false
  config.logger = ActiveSupport::Logger.new(nil)
  config.secret_key_base = "test"

  config.x.app = Studio::Settings.build(config_for(:app))
end

DummyApp.initialize!
