ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3::memory:"

require "rails"
require "action_controller/railtie"
require "action_mailer/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "erb"
require "propshaft"
require "studio/admin"
require "studio/auth/test_helper"
require "flipper/adapters/memory"
require "minitest/autorun"
require "mocha/minitest"

DUMMY_ROOT = File.expand_path("dummy", __dir__)
FileUtils.mkdir_p(File.join(DUMMY_ROOT, "log"))
FileUtils.mkdir_p(File.join(DUMMY_ROOT, "tmp"))

class DummyApp < Rails::Application
  config.load_defaults 8.1
  config.root = DUMMY_ROOT
  config.eager_load = false
  config.logger = ActiveSupport::Logger.new(nil)
  config.secret_key_base = "test"
  config.hosts.clear
  config.cache_store = :memory_store
  config.active_job.queue_adapter = :test
  config.action_mailer.delivery_method = :test
end

Studio::Auth.configure do |c|
  c.app_name = "Dummy"
  c.mail_from = "Dummy <hello@dummy.app>"
  c.support_email = "support@dummy.app"
  c.mail_logo_url = "https://dummy.app/mail/logo.png"
  c.terms_url = "https://dummy.app/terms"
  c.privacy_url = "https://dummy.app/privacy"
  c.session_idle_timeout = 20.years
  c.session_absolute_timeout = 20.years
end

Flipper.configure { |config| config.adapter { Flipper::Adapters::Memory.new } }

DummyApp.initialize!

ActiveRecord::Schema.verbose = false
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :email_address, null: false, index: {unique: true}
    t.timestamps
  end
end

template = Gem::Specification.find_by_name("studio-auth").gem_dir + "/lib/generators/studio/auth/templates/create_studio_auth.rb.tt"
rendered = File.join(DUMMY_ROOT, "tmp/create_studio_auth.rb")
File.write(rendered, ERB.new(File.read(template)).result)
require rendered
CreateStudioAuth.migrate(:up)

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class User < ApplicationRecord
  include Studio::Auth::ForUser
end

class Session < ApplicationRecord
  include Studio::Auth::ForSession
end

class Current < ActiveSupport::CurrentAttributes
  attribute :session
end

DummyApp.routes.draw do
  studio_auth
  root to: "pages#show"
  studio_admin do
    root "dashboard#show"
    resources :users, only: [:index, :create]
    get "unguarded", to: "unguarded#show"
  end
end

class ApplicationController < ActionController::Base
  include Studio::Auth::ForController
end

class PagesController < ApplicationController
  allow_unauthenticated_access

  def show
    render plain: "home"
  end
end

class AdminBaseController < ApplicationController
  include Studio::Admin::ForAdminController
end

module Admin
  class DashboardController < AdminBaseController
    def show
      render plain: "dashboard"
    end
  end

  class UnguardedController < ApplicationController
    def show
      render plain: "unguarded"
    end
  end

  class UsersController < AdminBaseController
    def index
      render plain: "users"
    end

    def create
      head :created
    end
  end
end

class ActionDispatch::IntegrationTest
  include Studio::Auth::TestHelper

  private

  def without_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    yield
  ensure
    ActionController::Base.allow_forgery_protection = true
  end
end

class ActiveSupport::TestCase
  teardown do
    Studio::Auth::KnownDevice.delete_all
    Studio::Auth::LoginCode.delete_all
    Session.delete_all
    User.delete_all
  end
end
