ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3::memory:"

require "rails"
require "action_controller/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "global_id/railtie"
require "erb"
require "studio/billing"
require "minitest/autorun"
require "mocha/minitest"
require "active_support/testing/time_helpers"

DUMMY_ROOT = File.expand_path("dummy", __dir__)
FileUtils.mkdir_p(File.join(DUMMY_ROOT, "config"))
FileUtils.mkdir_p(File.join(DUMMY_ROOT, "tmp"))
FileUtils.mkdir_p(File.join(DUMMY_ROOT, "log"))

module StudioBillingFixtures
  API_VERSION = "2026-09-30.endive"
  WEBHOOK_URL = "https://app.example.test/billing/webhooks"
  WEBHOOK_SECRET = "whsec_test_studio_billing"

  CATALOG = {
    "default_plan" => "free",
    "tax" => {"behavior" => "inclusive", "code" => "txcd_10103001"},
    "plans" => [
      {"code" => "free", "name" => "Free", "limits" => {"new_jobs" => 20, "texts" => 0, "locations" => 1}},
      {
        "code" => "team",
        "name" => "Team",
        "description" => "For independent shops",
        "features" => ["texts", "remove_branding"],
        "limits" => {"new_jobs" => 200, "texts" => 250, "locations" => "unlimited"},
        "prices" => [
          {"lookup_key" => "team_yearly", "interval" => "year", "amounts" => {"CAD" => 590, "USD" => 430}},
          {"lookup_key" => "team_monthly", "interval" => "month", "amounts" => {"CAD" => "69.00"}}
        ]
      },
      {
        "code" => "simple",
        "name" => "Simple",
        "legacy" => true,
        "entitlements_of" => "team",
        "prices" => [{"lookup_key" => "simple_yearly", "interval" => "year", "amounts" => {"CAD" => 348}}]
      }
    ],
    "branding" => {
      "display_name" => "Workbench",
      "background_color" => "#ffffff",
      "button_color" => "#1f1f1f",
      "border_style" => "rounded",
      "icon_url" => "https://useworkbench.co/icon.png"
    },
    "portal" => {"business_profile" => {"headline" => "Manage your Workbench plan"}}
  }.freeze

  class << self
    def configure!
      Studio::Billing.configure do |c|
        c.api_key = "sk_test_studio_billing"
        c.api_version = API_VERSION
        c.product_name = "Workbench"
        c.webhook_url = WEBHOOK_URL
        c.webhook_secret = WEBHOOK_SECRET
        c.portal_configuration_id = "bpc_test"
        c.owner_classes = ["Organization"]
        c.catalog_path = File.join(DUMMY_ROOT, "config/billing.yml")
        c.usage(:new_jobs, per: :month) { |owner, period| owner.jobs.where(created_at: period).count }
        c.usage(:texts, per: :month) { |_owner, _period| 0 }
        c.usage(:locations) { |owner| owner.locations_count }
      end
    end
  end
end

File.write(File.join(DUMMY_ROOT, "config/billing.yml"), StudioBillingFixtures::CATALOG.to_yaml)

class DummyApp < Rails::Application
  config.root = DUMMY_ROOT
  config.eager_load = false
  config.logger = ActiveSupport::Logger.new(nil)
  config.secret_key_base = "test"
  config.hosts.clear
  config.active_job.queue_adapter = :test
  config.time_zone = "America/Toronto"
end

StudioBillingFixtures.configure!
DummyApp.initialize!

DummyApp.routes.draw do
  studio_billing
end

ActiveRecord::Schema.verbose = false
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table :organizations do |t|
    t.string :name
    t.integer :locations_count, default: 1, null: false
    t.string :stripe_customer_id, index: {unique: true}
    t.timestamps
  end

  create_table :jobs do |t|
    t.references :organization
    t.timestamps
  end
end

template = File.expand_path("../lib/generators/studio/billing/templates/create_studio_billing.rb.tt", __dir__)
rendered = File.join(DUMMY_ROOT, "tmp/create_studio_billing.rb")
File.write(rendered, ERB.new(File.read(template)).result)
require rendered
CreateStudioBilling.migrate(:up)

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class Organization < ApplicationRecord
  include Studio::Billing::ForOwner

  has_many :jobs

  def billing_email_address = "owner@example.test"
end

class Job < ApplicationRecord
  belongs_to :organization
end

class StudioBillingTestCase < ActiveSupport::TestCase
  include StudioBillingFixtures
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Studio::Billing.reset!
    StudioBillingFixtures.configure!
    Studio::Billing.stubs(:client).returns(client)
  end

  teardown do
    [Studio::Billing::WebhookEvent, Studio::Billing::SyncCursor, Studio::Billing::Grant,
      Studio::Billing::Subscription, Job, Organization].each(&:delete_all)
    Studio::Billing.reset!
    StudioBillingFixtures.configure!
  end

  private

  def catalog(data = CATALOG)
    Studio::Billing::Catalog.new(data)
  end

  def client
    @client ||= Stripe::StripeClient.new("sk_test_studio_billing", stripe_version: API_VERSION)
  end

  def stripe_object(attributes)
    Stripe::StripeObject.construct_from(attributes)
  end

  def stripe_list(*objects)
    Stripe::ListObject.construct_from({object: "list", data: objects, has_more: false})
  end

  def resource_missing
    Stripe::InvalidRequestError.new("No such product", "id", code: "resource_missing")
  end

  def organization
    @organization ||= Organization.create!(name: "Fort Richmond Jewellers")
  end

  def stripe_subscription(id: "sub_1", status: "active", lookup_key: "team_yearly", period_end: 30.days.from_now,
    customer: "cus_1", owner: organization, cancel_at: nil)
    stripe_object(
      id: id, object: "subscription", customer: customer, status: status,
      cancel_at: cancel_at&.to_i,
      metadata: owner ? {Studio::Billing::OWNER_METADATA_KEY => owner.billing_global_id} : {},
      items: {object: "list", data: [{
        id: "si_1", object: "subscription_item", current_period_end: period_end.to_i,
        price: {id: "price_#{lookup_key}", object: "price", lookup_key: lookup_key}
      }]}
    )
  end

  def subscribe(organization, lookup_key: "team_yearly", status: "active", period_end: 30.days.from_now)
    subscription = Studio::Billing::SubscriptionSync.new(client: client)
      .call(stripe_subscription(id: "sub_#{SecureRandom.hex(4)}", lookup_key:, status:, period_end:,
        owner: organization, customer: "cus_#{organization.id}"))
    organization.reload
    subscription
  end
end
