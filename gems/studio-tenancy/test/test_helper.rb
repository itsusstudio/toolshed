ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3::memory:"

require "rails"
require "action_controller/railtie"
require "action_mailer/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "erb"
require "studio/tenancy"
require "minitest/autorun"
require "mocha/minitest"

DUMMY_ROOT = File.expand_path("dummy", __dir__)
FileUtils.mkdir_p(File.join(DUMMY_ROOT, "log"))
FileUtils.mkdir_p(File.join(DUMMY_ROOT, "tmp"))

class DummyApp < Rails::Application
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

DummyApp.initialize!

ActiveRecord::Schema.verbose = false
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :email_address, null: false, index: {unique: true}
    t.string :name, null: false
    t.timestamps
  end
end

def run_template_migration(gem_name, migration_class)
  template = Gem::Specification.find_by_name(gem_name).gem_dir +
    "/lib/generators/studio/#{gem_name.delete_prefix("studio-")}/templates/#{migration_class.underscore}.rb.tt"
  rendered = File.join(DUMMY_ROOT, "tmp/#{migration_class.underscore}.rb")
  File.write(rendered, ERB.new(File.read(template)).result)
  require rendered
  migration_class.constantize.migrate(:up)
end

run_template_migration("studio-auth", "CreateStudioAuth")
# Runs the migration the install generator writes, so the tests cover it.
run_template_migration("studio-tenancy", "CreateStudioTenancy")

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class User < ApplicationRecord
  include Studio::Auth::ForUser
  include Studio::Tenancy::ForUser
end

class Session < ApplicationRecord
  include Studio::Auth::ForSession
end

class Organization < ApplicationRecord
  include Studio::Tenancy::ForOrganization
end

class OrganizationMembership < ApplicationRecord
  include Studio::Tenancy::ForOrganizationMembership
end

class Workspace < ApplicationRecord
  include Studio::Tenancy::ForWorkspace
end

class WorkspaceMembership < ApplicationRecord
  include Studio::Tenancy::ForWorkspaceMembership
end

class Current < ActiveSupport::CurrentAttributes
  attribute :session
end

DummyApp.routes.draw do
  studio_auth
  root to: "pages#organization"
  get "/organization", to: "pages#organization"
  get "/workspace", to: "pages#workspace"
end

class ApplicationController < ActionController::Base
  include Studio::Auth::ForController
  include Studio::Tenancy::ForController
end

class PagesController < ApplicationController
  allow_unauthenticated_access

  def organization
    render plain: current_organization&.id.to_s
  end

  def workspace
    render plain: current_workspace&.id.to_s
  end
end

class ActiveSupport::TestCase
  teardown do
    Studio::Auth::KnownDevice.delete_all
    Studio::Auth::LoginCode.delete_all
    Session.delete_all
    WorkspaceMembership.delete_all
    OrganizationMembership.delete_all
    Workspace.delete_all
    Organization.delete_all
    User.delete_all
  end

  private

  def create_user(name = "Cook")
    User.create!(name: name, email_address: "#{name.downcase}@studio.com")
  end
end
