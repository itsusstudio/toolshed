require "test_helper"

class Studio::Tenancy::UserTest < ActiveSupport::TestCase
  test "#create! gives the user an organization and a first workspace in it, both theirs" do
    user = create_user

    workspace = user.default_workspace
    assert_equal user.name, workspace.name
    assert_equal user, workspace.organization.owner
    assert_predicate user.workspace_memberships.sole, :owner?
  end

  test "#default_workspace falls back to the oldest workspace the user owns" do
    user = create_user
    first = user.default_workspace
    user.default_workspace_membership.update!(is_default: false)
    first.organization.workspaces.create!(name: "Later").workspace_memberships.create!(user: user, role: :owner)

    assert_equal first, user.reload.default_workspace
  end

  test "#destroy! removes the user's organizations and their workspaces, not workspaces they joined" do
    host = create_user("Host")
    partner = create_user("Partner")
    shared = host.default_workspace
    shared.workspace_memberships.create!(user: partner, role: :member)
    own = partner.default_workspace

    partner.destroy!

    assert_equal [host.id], shared.workspace_memberships.pluck(:user_id)
    refute Workspace.exists?(own.id)
    refute Organization.exists?(own.organization_id)
  end
end
