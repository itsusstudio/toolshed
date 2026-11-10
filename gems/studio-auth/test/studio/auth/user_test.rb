require "test_helper"

class Studio::Auth::UserTest < ActiveSupport::TestCase
  test "an email address is required and must look like one" do
    assert_includes User.new(email_address: "").tap(&:valid?).errors[:email_address], "can't be blank"
    assert_includes User.new(email_address: "garbage").tap(&:valid?).errors[:email_address], "is invalid"
  end

  test "an email address is unique however it is typed" do
    User.create!(email_address: "taken@studio.com")

    assert_includes User.new(email_address: " TAKEN@studio.com").tap(&:valid?).errors[:email_address], "has already been taken"
  end

  test "a destroyed user takes their sessions, codes and devices along" do
    user = User.create!(email_address: "cook@studio.com")
    user.sessions.create!
    Studio::Auth::DeviceCookie.new(ActionDispatch::TestRequest.create.cookie_jar).remember_for(user, user_agent: "test", ip_address: "1.2.3.4")

    user.destroy!

    assert_equal 0, Session.count
    assert_equal 0, Studio::Auth::KnownDevice.count
  end
end
