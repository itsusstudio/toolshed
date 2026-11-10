require "test_helper"
require "rails/generators/test_case"
require "generators/studio/tenancy/install_generator"

class Studio::Tenancy::InstallGeneratorTest < Rails::Generators::TestCase
  tests Studio::Tenancy::Generators::InstallGenerator
  destination File.join(DUMMY_ROOT, "tmp/generator")
  setup :prepare_destination

  test "writes the migration and the models" do
    run_generator

    assert_migration "db/migrate/create_studio_tenancy.rb", /create_table :organization_memberships/
    assert_file "app/models/organization.rb", /include Studio::Tenancy::ForOrganization/
    assert_file "app/models/organization_membership.rb", /include Studio::Tenancy::ForOrganizationMembership/
    assert_file "app/models/workspace.rb", /include Studio::Tenancy::ForWorkspace/
    assert_file "app/models/workspace_membership.rb", /include Studio::Tenancy::ForWorkspaceMembership/
  end
end
