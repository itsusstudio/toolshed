require "test_helper"

class Studio::Auth::UserTest < ActiveSupport::TestCase
  test "an email address is required and must look like one" do
    assert_includes User.new(email_address: "").tap(&:valid?).errors[:email_address], "can't be blank"
    assert_includes User.new(email_address: "garbage").tap(&:valid?).errors[:email_address], "is invalid"
  end

  test "a new or changed email address must be able to receive mail" do
    disposable = User.new(email_address: "cook@mailinator.com").tap(&:valid?)
    assert_includes disposable.errors[:email_address], "can't receive email"

    user = User.create!(email_address: "cook@studio.com")
    user.stubs(:can_sign_in?).returns(false)
    user.email_address = "deleted-1@deleted.invalid"
    assert_predicate user, :valid?
  end

  test "an email address is unique however it is typed" do
    User.create!(email_address: "taken@studio.com")

    duplicate = User.new(email_address: " TAKEN@studio.com").tap(&:valid?)
    assert_includes duplicate.errors[:email_address], "has already been taken"
  end

  test "unlock_sign_in! lifts a lockout at once" do
    user = User.create!(email_address: "cook@studio.com")
    user.login_codes.create!(
      code_digest: "d", expires_at: 1.minute.from_now,
      failed_attempts: Studio::Auth::LoginCode::LOCKOUT_WRONG_CODES, failed_at: Time.current
    )
    assert user.sign_in_locked?

    user.unlock_sign_in!

    refute user.sign_in_locked?
  end

  test "a destroyed user takes their sessions, codes and devices along" do
    user = User.create!(email_address: "cook@studio.com")
    user.sessions.create!
    device_cookie = Studio::Auth::DeviceCookie.new(ActionDispatch::TestRequest.create.cookie_jar)
    device_cookie.trust_for(user, user_agent: "test", ip_address: "1.2.3.4")

    user.destroy!

    assert_equal 0, Session.count
    assert_equal 0, Studio::Auth::KnownDevice.count
  end
end
