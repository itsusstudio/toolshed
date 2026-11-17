require "test_helper"

class Studio::Admin::RoutesTest < ActionDispatch::IntegrationTest
  test "the app's admin pages live under /admin, in Admin::" do
    sign_in_as(staff)

    get admin_root_path
    assert_equal "dashboard", response.body

    get admin_users_path
    assert_equal "users", response.body
  end

  test "the admin tools open for staff" do
    sign_in_as(staff)

    get "/admin/flipper/features"

    assert_response :success
  end

  test "the admin tools and pages send everyone else to the app's root" do
    sign_in_as(User.create!(email_address: "cook@studio.com"))

    ["/admin", "/admin/users", "/admin/flipper", "/admin/jobs", "/admin/pghero", "/admin/nowhere"].each do |path|
      get path
      assert_redirected_to root_path, path
    end
  end

  test "an admin page whose controller skips the staff checks still opens only for staff" do
    sign_in_as(User.create!(email_address: "cook@studio.com"))

    get "/admin/unguarded"

    assert_redirected_to root_path
  end

  test "staff fresh enough to read a tool sign in again to change anything in it" do
    Studio::Admin.config.stubs(:read_sign_in_max_age).returns(1.year)
    sign_in_as(staff)

    travel Studio::Admin::Configuration::WRITE_SIGN_IN_MAX_AGE_LIMIT + 1.hour do
      get "/admin/flipper/features"
      assert_response :success

      without_forgery_protection { post "/admin/flipper/features", params: {value: "beta"} }
      assert_redirected_to login_path
      assert_not Flipper.exist?(:beta)
    end
  end

  test "a signed-out visitor is sent to sign in from a tool" do
    get "/admin/pghero"

    assert_redirected_to login_path
  end

  test "an admin path nothing matched sends staff to the admin dashboard" do
    sign_in_as(staff)

    get "/admin/nowhere"

    assert_redirected_to admin_root_path
  end

  test "Mission Control runs behind the app's AdminBaseController, without its HTTP basic auth" do
    sign_in_as(staff)

    get "/admin/jobs"

    refute_equal 401, response.status
    assert_equal "AdminBaseController", MissionControl::Jobs.base_controller_class
  end

  private

  def staff
    User.create!(email_address: "boss@itsusstudio.com", staff: true)
  end
end
