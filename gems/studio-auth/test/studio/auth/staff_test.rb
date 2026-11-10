require "test_helper"

class Studio::Auth::StaffTest < ActionDispatch::IntegrationTest
  include Studio::Auth::TestHelper

  test "a signed-out visitor is sent to sign in" do
    get "/admin"

    assert_redirected_to login_path
  end

  test "a signed-in user who isn't staff gets a 404" do
    sign_in_as(User.create!(email_address: "cook@studio.com"))

    get "/admin"

    assert_response :not_found
  end

  test "a staff flag on an address outside the studio domain opens nothing" do
    outsider = User.create!(email_address: "boss@gmail.com")
    outsider.update_column(:staff, true)
    sign_in_as(outsider)

    get "/admin"

    assert_response :not_found
    refute_includes User.staff, outsider
  end

  test "staff can't be saved on an address outside the studio domain" do
    user = User.new(email_address: "boss@itsusstudio.com.evil.com", staff: true)

    refute_predicate user, :valid?
    assert_includes user.errors.details[:staff], {error: :studio_email_only, domain: "itsusstudio.com"}
  end

  test "staff get in, and the page is kept out of search engines" do
    sign_in_as(User.create!(email_address: "boss@itsusstudio.com", staff: true))

    get "/admin"

    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end

  test "staff signed in too long ago sign in again and come back" do
    sign_in_as(User.create!(email_address: "boss@itsusstudio.com", staff: true))

    travel Studio::Auth::Configuration::STAFF_WRITE_SIGN_IN_MAX_AGE_LIMIT + 1.minute do
      get "/admin/users"

      assert_redirected_to login_path
      assert_equal 0, Session.count
      post verify_path, params: {code: request_authentication_code("boss@itsusstudio.com")}
      assert_redirected_to "/admin/users"
    end
  end

  test "a read-only session can view but signs in again to change anything" do
    Studio::Auth.config.stubs(:staff_read_sign_in_max_age).returns(30.days)
    sign_in_as(User.create!(email_address: "boss@itsusstudio.com", staff: true))

    travel 1.day do
      get "/admin/users"
      assert_response :success

      post "/admin/users", headers: {"Referer" => "http://www.example.com/admin/users?page=2"}
      assert_redirected_to login_path
      post verify_path, params: {code: request_authentication_code("boss@itsusstudio.com")}
      assert_redirected_to "/admin/users"
    end
  end

  test "a change in the admin area is recorded" do
    staff = User.create!(email_address: "boss@itsusstudio.com", staff: true)
    sign_in_as(staff)
    assert_event_reported("authentication.admin_action", payload: {actor_id: staff.id, method: "POST"}) do
      post "/admin/users"
    end
  end

  test "a mounted engine opens only for staff who signed in recently" do
    sign_in_as(User.create!(email_address: "boss@itsusstudio.com", staff: true))
    get "/admin/engine"
    assert_equal "engine", response.body

    travel Studio::Auth::Configuration::STAFF_WRITE_SIGN_IN_MAX_AGE_LIMIT + 1.minute do
      get "/admin/engine"
      assert_redirected_to login_path
    end
  end

  test "a mounted engine falls through to the 404 for everyone else" do
    sign_in_as(User.create!(email_address: "cook@studio.com"))

    get "/admin/engine"

    assert_response :not_found
  end

  private

  def request_authentication_code(email_address)
    perform_enqueued_jobs { post login_path, params: {email_address: email_address} }
    ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
  end
end
