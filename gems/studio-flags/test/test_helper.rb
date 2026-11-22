ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3::memory:"

require "rails"
require "active_record/railtie"
require "studio/flags"
require "studio/flags/test_helper"
require "minitest/autorun"
require "mocha/minitest"

# test/dummy is gitignored, so the registry is written at boot.
FileUtils.mkdir_p(File.expand_path("dummy/config", __dir__))
File.write(File.expand_path("dummy/config/feature_flags.yml", __dir__), <<~YAML)
  feature_enable_bella:
    description: "On: Bella answers. Off: hidden."

  killswitch_bookmark_details_cache:
    description: "On: caching killed."

  feature_enable_bare:
YAML

class DummyApp < Rails::Application
  config.root = File.expand_path("dummy", __dir__)
  config.eager_load = false
  config.logger = ActiveSupport::Logger.new(nil)
  config.secret_key_base = "test"
end

DummyApp.initialize!
DummyApp.load_tasks

Flipper.configure { |config| config.adapter { Flipper::Adapters::Memory.new } }

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:people) { |t| t.string :name }
  create_table(:shops) { |t| t.string :name }
end

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class Person < ApplicationRecord
  def flipper_actor_name = "#{name} (person)"
end

class Shop < ApplicationRecord
end
