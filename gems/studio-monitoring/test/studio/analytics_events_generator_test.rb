require "test_helper"
require "rails/generators/test_case"
require "generators/studio/monitoring/analytics_events_generator"

class Studio::Monitoring::AnalyticsEventsGeneratorTest < Rails::Generators::TestCase
  tests Studio::Monitoring::AnalyticsEventsGenerator
  destination File.expand_path("../../tmp/generator", __dir__)
  setup :prepare_destination

  test "creates the analytics_events migration" do
    run_generator

    assert_migration "db/migrate/create_analytics_events.rb" do |migration|
      assert_match "create_table :analytics_events", migration
      assert_match "t.bigint :tenant_id", migration
      assert_match "t.index :properties, using: :gin", migration
    end
  end
end
