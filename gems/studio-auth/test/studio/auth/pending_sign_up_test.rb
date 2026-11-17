require "test_helper"

class Studio::Auth::PendingSignUpTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PendingSignUp = Studio::Auth::PendingSignUp

  test ".record! keeps one row per address and refreshes it" do
    first = PendingSignUp.record!(email_address: "Cook@Studio.com", full_name: "Cook", time_zone: "America/Toronto")

    travel 1.day do
      again = PendingSignUp.record!(email_address: "cook@studio.com", full_name: "Head Cook")

      assert_equal first.id, again.id
      assert_equal "Head Cook", again.full_name
      assert_nil again.time_zone
      assert_in_delta PendingSignUp::TTL.from_now, again.expires_at, 1.second
    end
    assert_equal 1, PendingSignUp.count
  end

  test ".record! drops a time zone the app wouldn't know" do
    pending = PendingSignUp.record!(email_address: "cook@studio.com", full_name: "Cook", time_zone: "Mars/Olympus")

    assert_nil pending.time_zone
  end

  test ".from_cookie finds a live sign-up and ignores an expired one" do
    pending = PendingSignUp.record!(email_address: "cook@studio.com", full_name: "Cook")
    jar = ActionDispatch::TestRequest.create.cookie_jar
    pending.write_cookie(jar)

    assert_equal pending, PendingSignUp.from_cookie(jar)
    travel PendingSignUp::TTL + 1.second do
      assert_nil PendingSignUp.from_cookie(jar)
    end
  end

  test "the purge deletes expired sign-ups and keeps live ones" do
    PendingSignUp.record!(email_address: "old@studio.com", full_name: "Old")
    travel PendingSignUp::TTL + 1.second
    PendingSignUp.record!(email_address: "new@studio.com", full_name: "New")

    Studio::Auth::PurgeExpiredJob.perform_now

    assert_equal ["new@studio.com"], PendingSignUp.pluck(:email_address)
  end

  test "an address with a pending sign-up gets a code on the sign-in page, not the new-account page" do
    PendingSignUp.record!(email_address: "cook@studio.com", full_name: "Cook")

    post login_path, params: {email_address: "cook@studio.com"}

    assert_redirected_to verify_path
  end

  test "accepting an invitation ends a pending sign-up for the same address" do
    owner = User.create!(email_address: "owner@studio.com")
    invitee = User.create!(email_address: "placeholder@studio.com")
    PendingSignUp.record!(email_address: "cook@studio.com", full_name: "Cook")
    invitation = Studio::Auth::Invitation.invite!(user: invitee, email_address: "cook@studio.com", invited_by: owner)

    invitation.accept!

    assert_not PendingSignUp.exists?(email_address: "cook@studio.com")
  end
end
