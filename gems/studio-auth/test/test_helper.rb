ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3::memory:"

require "rails"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_cable/engine"
require "active_job/railtie"
require "active_record/railtie"
require "erb"
require "studio/auth"
require "minitest/autorun"
require "mocha/minitest"

DUMMY_ROOT = File.expand_path("dummy", __dir__)
FileUtils.mkdir_p(File.join(DUMMY_ROOT, "log"))
FileUtils.mkdir_p(File.join(DUMMY_ROOT, "tmp"))

# The gem's auth layout renders inside the app's Uniform document layout,
# which yields the gem's page block.
FileUtils.rm_rf(File.join(DUMMY_ROOT, "app/views"))
FileUtils.mkdir_p(File.join(DUMMY_ROOT, "app/views/layouts"))
File.write(File.join(DUMMY_ROOT, "app/views/layouts/application.html.erb"),
  "<html><head><%= yield :head %></head><body><%= content_for?(:studio_auth_page) ? yield(:studio_auth_page) : yield %></body></html>")

class DummyApp < Rails::Application
  config.root = DUMMY_ROOT
  config.eager_load = false
  config.logger = ActiveSupport::Logger.new(nil)
  config.secret_key_base = "test"
  config.hosts.clear
  config.cache_store = :memory_store
  config.active_job.queue_adapter = :test
  config.action_mailer.delivery_method = :test
  config.action_cable.cable = {"adapter" => "test"}
  config.action_mailer.default_url_options = {host: "example.test"}
  config.i18n.available_locales = [:en, :fr, :nl]
end

Studio::Auth.configure do |c|
  c.app_name = "Dummy"
  c.mail_from = "Dummy <hello@dummy.app>"
  c.mail_address = ["Dummy", "1 Main Street", "Toronto ON"]
  c.terms_url = "https://dummy.app/terms"
  c.privacy_url = "https://dummy.app/privacy"
  c.session_idle_timeout = 30.days
  c.session_absolute_timeout = 90.days
end

DummyApp.initialize!

ActiveRecord::Schema.verbose = false
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :email_address, index: {unique: true}
    t.string :locale
    t.timestamps
  end
end

# Runs the migration the install generator writes, so the tests cover it.
template = File.expand_path("../lib/generators/studio/auth/templates/create_studio_auth.rb.tt", __dir__)
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
  get "/private", to: "pages#private"
  post "/signup", to: "signups#create"
  post "/signup_code", to: "signups#code"
  get "/signup_verified", to: "signups#verified"
end

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include Studio::Auth::ForCableConnection
  end
end

class ApplicationController < ActionController::Base
  include Studio::Auth::ForController

  private

  def create_account_for(email_address)
    User.create!(email_address: email_address)
  end
end

class PagesController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    render plain: [authenticated?, authenticated?].map { it ? "in" : "out" }.join(" ")
  end

  def private
    render plain: "private"
  end
end

class SignupsController < ApplicationController
  allow_unauthenticated_access

  def create
    user = User.find_by(email_address: params[:email_address]) || User.create!(email_address: params[:email_address])
    start_sign_in_for(user)
  end

  def code
    start_sign_up_for(params[:email_address])
  end

  def verified
    render plain: [verified_email_address?(params[:email_address]), verified_email_address].join(" ")
  end
end

module AuthenticationTestHelpers
  def create_authentication_user(email_address)
    User.create!(email_address: email_address)
  end

  def sign_in_with_code(email_address)
    create_authentication_user(email_address) if !User.exists?(email_address: email_address)
    post verify_path, params: {code: request_authentication_code(email_address)}
  end
end

class ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  teardown do
    travel_back
    Studio::Auth::KnownDevice.delete_all
    Studio::Auth::LoginCode.delete_all
    Studio::Auth::Invitation.delete_all
    Session.delete_all
    User.delete_all
    Rails.cache.clear
    ActionMailer::Base.deliveries.clear
  end
end
