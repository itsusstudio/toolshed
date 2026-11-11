require "test_helper"

class Studio::Auth::StaffTest < ActiveSupport::TestCase
  test "a staff flag on an address outside the studio domain isn't staff" do
    outsider = User.create!(email_address: "boss@gmail.com")
    outsider.update_column(:staff, true)

    refute_predicate outsider, :staff?
    refute_includes User.staff, outsider
  end

  test "staff can't be saved on an address outside the studio domain" do
    user = User.new(email_address: "boss@itsusstudio.com.evil.com", staff: true)

    refute_predicate user, :valid?
    assert_includes user.errors.details[:staff], {error: :studio_email_only, domain: "itsusstudio.com"}
  end

  test "an app review account is never staff" do
    Rails.application.credentials.stubs(:dig).with(:studio_auth, :app_review_accounts)
      .returns({"apple+review@itsusstudio.com": "424242"})
    reviewer = User.create!(email_address: "apple+review@itsusstudio.com")

    reviewer.staff = true
    refute_predicate reviewer, :valid?
    assert_includes reviewer.errors.details[:staff], {error: :app_review_account}

    reviewer.update_column(:staff, true)
    refute_predicate reviewer, :staff?
    refute_includes User.staff, reviewer
  end
end
