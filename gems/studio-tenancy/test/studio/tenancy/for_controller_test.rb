require "test_helper"

class Studio::Tenancy::ForControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "the signed-in user works in their default workspace, in their own organization" do
    user = create_user
    sign_in(user)

    get "/workspace"
    assert_equal user.default_workspace.id.to_s, response.body
    get "/organization"
    assert_equal user.default_workspace.organization_id.to_s, response.body
  end

  test "someone invited into a workspace works under the host's organization, without joining it" do
    host = create_user("Host")
    partner = create_user("Partner")
    shared = host.default_workspace
    partner.default_workspace_membership.update!(is_default: false)
    shared.workspace_memberships.create!(user: partner, role: :member, is_default: true)
    sign_in(partner)

    get "/workspace"
    assert_equal shared.id.to_s, response.body
    get "/organization"
    assert_equal shared.organization_id.to_s, response.body
  end

  test "everything is nil when signed out" do
    ["/workspace", "/organization"].each do |path|
      get path
      assert_equal "", response.body.strip, path
    end
  end

  private

  def sign_in(user)
    perform_enqueued_jobs { post login_path, params: {email_address: user.email_address} }
    code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
    post verify_path, params: {code: code}
  end
end
