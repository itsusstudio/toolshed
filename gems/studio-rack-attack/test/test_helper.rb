ENV["RAILS_ENV"] = "test"

require "rails"
require "action_controller/railtie"
require "studio-rack-attack"  # the path Bundler requires
require "studio/monitoring/test_helper"
require "minitest/autorun"

# test/dummy is gitignored, so its files are written at boot.
FileUtils.mkdir_p(File.expand_path("dummy/log", __dir__))
FileUtils.mkdir_p(File.expand_path("dummy/public", __dir__))
File.write(File.expand_path("dummy/public/429.html", __dir__), "<h1>Slow down</h1>\n")

class DummyApp < Rails::Application
  config.root = File.expand_path("dummy", __dir__)
  config.eager_load = false
  config.logger = ActiveSupport::Logger.new(nil)
  config.secret_key_base = "test"
  config.hosts.clear
end

Studio::Monitoring.configure { |c| c.service_name = "dummy" }

DummyApp.initialize!

DummyApp.routes.draw do
  get "/up", to: "pages#show"
  get "/recipes", to: "pages#show"
  get "/assets/app.css", to: "pages#show"
  get "*path", to: "pages#show", format: false
end

class ApplicationController < ActionController::Base
end

class PagesController < ApplicationController
  def show
    head :ok
  end
end

class ActiveSupport::TestCase
  include Studio::Monitoring::TestHelper
end
