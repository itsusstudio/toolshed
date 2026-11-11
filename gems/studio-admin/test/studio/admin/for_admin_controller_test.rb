require "test_helper"

class Studio::Admin::ForAdminControllerTest < ActionDispatch::IntegrationTest
  test "staff get in, and the page is kept out of search engines" do
    sign_in_as(staff)

    get "/admin/users"

    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end

  test "staff signed in too long ago sign in again and come back" do
    sign_in_as(staff)

    travel Studio::Admin::Configuration::WRITE_SIGN_IN_MAX_AGE_LIMIT + 1.minute do
      get "/admin/users"

      assert_redirected_to login_path
      assert_equal 0, Session.count
      sign_in_again("boss@itsusstudio.com")
      assert_redirected_to "/admin/users"
    end
  end

  test "a write too long after sign-in returns to the form's page after signing in again" do
    Studio::Admin.config.stubs(:read_sign_in_max_age).returns(30.days)
    sign_in_as(staff)

    travel 1.day do
      without_forgery_protection do
        post "/admin/users", headers: {"Referer" => "http://www.example.com/admin/users?page=2"}
      end
      assert_redirected_to login_path
      sign_in_again("boss@itsusstudio.com")
      assert_redirected_to "/admin/users"
    end
  end

  test "a change in the admin area is recorded" do
    boss = staff
    sign_in_as(boss)

    assert_event_reported("admin.action", payload: {actor_id: boss.id, method: "POST"}) do
      without_forgery_protection { post "/admin/users" }
    end
  end

  test "writes allow a sign-in at most 12 hours old" do
    config = Studio::Admin::Configuration.new
    config.write_sign_in_max_age = 1.day

    error = assert_raises(Studio::Admin::Configuration::Error) { config.validate_config! }
    assert_match "c.write_sign_in_max_age can be at most 12 hours", error.message
  end

  private

  def staff
    User.create!(email_address: "boss@itsusstudio.com", staff: true)
  end

  def sign_in_again(email_address)
    without_forgery_protection do
      perform_enqueued_jobs { post login_path, params: {email_address: email_address} }
      post verify_path, params: {code: ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]}
    end
  end
end
