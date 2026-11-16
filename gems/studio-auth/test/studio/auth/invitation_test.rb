require "test_helper"

class Studio::Auth::InvitationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  Invitation = Studio::Auth::Invitation

  setup do
    @owner = User.create!(email_address: "owner@studio.com")
    User.any_instance.stubs(:requires_email_address?).returns(false)
    @member = User.create!(email_address: nil)
  end

  test ".invite! mails a link to the address and stores only the token's digest" do
    perform_enqueued_jobs { invite("Dana@Studio.com") }

    mail = ActionMailer::Base.deliveries.last
    assert_equal ["dana@studio.com"], mail.to
    token = invitation_token_from(mail)
    refute_includes Invitation.pluck(:token_digest), token
    assert_equal @member, Invitation.find_pending_by_token(token).user
  end

  test ".invite! replaces an open invitation" do
    first = invite("dana@studio.com")
    second = invite("dana@studio.com")

    assert_predicate first.reload.revoked_at, :present?
    assert_equal second, @member.reload.open_invitation
  end

  test ".invite! refuses an address another user already has" do
    assert_raises(ActiveRecord::RecordInvalid) { invite("owner@studio.com") }
  end

  test "opening the link and joining gives the user the address and signs them in" do
    perform_enqueued_jobs { invite("dana@studio.com") }
    token = invitation_token_from(ActionMailer::Base.deliveries.last)

    get invitation_path(token: token)
    assert_response :success
    assert_select "#studio-auth-invitation-join"

    patch invitation_path(token: token)

    assert_response :see_other
    assert_equal "dana@studio.com", @member.reload.email_address
    assert_equal 1, @member.sessions.count
    assert_nil Invitation.find_pending_by_token(token)
  end

  test "an expired or revoked link goes back to sign in" do
    perform_enqueued_jobs { invite("dana@studio.com") }
    token = invitation_token_from(ActionMailer::Base.deliveries.last)
    @member.open_invitation.revoke!

    get invitation_path(token: token)

    assert_redirected_to login_path
  end

  private

  def invite(email_address)
    Invitation.invite!(user: @member, email_address: email_address, invited_by: @owner)
  end

  def invitation_token_from(mail)
    mail.text_part.body.to_s[%r{/invites/(\w+)}, 1]
  end
end
