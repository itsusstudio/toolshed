require "test_helper"
require "rails/generators/test_case"
require "generators/studio/billing/install_generator"

class Studio::Billing::InstallGeneratorTest < Rails::Generators::TestCase
  tests Studio::Billing::Generators::InstallGenerator
  destination File.join(DUMMY_ROOT, "tmp/generator")

  setup do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
    FileUtils.mkdir_p(File.join(destination_root, "app/models"))
    File.write(File.join(destination_root, "app/models/repair_shop.rb"), "class RepairShop < ApplicationRecord\nend\n")
  end

  test "puts the Stripe customer on the owner model's table and includes the concern" do
    run_generator ["RepairShop"]

    assert_migration "db/migrate/add_stripe_customer_id_to_repair_shops.rb" do |content|
      assert_match "add_column :repair_shops, :stripe_customer_id", content
      assert_match "algorithm: :concurrently", content
      assert_match "disable_ddl_transaction!", content
    end
    assert_file "config/initializers/studio_billing.rb", /c.owner_classes = \["RepairShop"\]/
    assert_file "app/models/repair_shop.rb", /include Studio::Billing::ForOwner/
  end

  test "defaults the owner to Organization" do
    run_generator

    assert_migration "db/migrate/add_stripe_customer_id_to_organizations.rb", /add_column :organizations/
  end

  test "writes the migration, initializer, catalog, route and hourly reconcile" do
    run_generator

    assert_migration "db/migrate/create_studio_billing.rb", /create_table :billing_subscriptions/
    assert_file "config/initializers/studio_billing.rb", /Studio::Billing.configure/
    assert_file "config/billing.yml", /branding:/
    assert_file "config/routes.rb", /studio_billing/
    assert_file "config/recurring.yml" do |content|
      assert_match "Studio::Billing::ReconcileSubscriptionsJob", content
      assert_match "Studio::Billing::CheckStripeJob", content
      assert_match "Studio::Billing::PurgeWebhookEventsJob", content
    end
  end

  test "leaves an existing reconcile schedule alone" do
    File.write(File.join(destination_root, "config/recurring.yml"),
      "production:\n  studio_billing_reconcile:\n    class: Studio::Billing::ReconcileSubscriptionsJob\n")

    run_generator

    assert_file "config/recurring.yml" do |content|
      assert_equal 1, content.scan("Studio::Billing::ReconcileSubscriptionsJob").size
    end
  end
end
