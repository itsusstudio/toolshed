ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3::memory:"

require "rails"
require "action_controller/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "studio/monitoring"
require "minitest/autorun"
require "mocha/minitest"

module TestContext
  mattr_accessor :platform
end

FileUtils.mkdir_p(File.expand_path("dummy/log", __dir__))

class DummyApp < Rails::Application
  config.root = File.expand_path("dummy", __dir__)
  config.eager_load = false
  config.logger = ActiveSupport::Logger.new(nil)
  config.secret_key_base = "test"
  config.hosts.clear
  config.active_job.queue_adapter = :inline
  config.filter_parameters += Studio::Monitoring::FILTER_PARAMETERS
end

Studio::Monitoring.configure do |c|
  c.service_name = "dummy"
  c.default_properties = -> { {platform: TestContext.platform} }
end

DummyApp.initialize!

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :analytics_events do |t|
    t.bigint :actor_id
    t.bigint :tenant_id
    t.string :event_name, null: false
    t.json :properties, null: false, default: {}
    t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
  end
end

DummyApp.routes.draw do
  get "/ping", to: "ping#show"
  get "/t/:token", to: "ping#show"
  get "/recipes/:id", to: "ping#show"
  get "/analytics_tag", to: "analytics_tag#show"
  get "/track", to: "track#show"
end

class ApplicationController < ActionController::Base
end

class TrackController < ApplicationController
  def show
    Studio::Monitoring::Analytics.track("page_viewed", actor_id: 1)
    head :ok
  end
end

class PingController < ApplicationController
  def show
    render json: {request_id: Studio::Monitoring::Current.request_id, session_id: Studio::Monitoring::Current.analytics_session_id}
  end
end

class ApplicationJob < ActiveJob::Base
end

class CleanupJob < ApplicationJob
  def perform
  end
end

class FrameworkJob < ActiveJob::Base # standard:disable Rails/ApplicationJob -- stands in for Turbo's jobs
  def perform
  end
end

class ActiveSupport::TestCase
  teardown do
    TestContext.platform = nil
    Studio::Monitoring::Current.reset
  end
end
