require "test_helper"

class Studio::Auth::SignUpsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Studio::Auth::TestHelper

  test "the signup page asks for a full name and an email address, and carries the time zone" do
    get signup_path

    assert_response :success
    assert_select "form#studio-auth-sign-up-form[action=?]", signup_path do
      assert_select "input[name=full_name][autocomplete=name]"
      assert_select "input[name=email_address][autocomplete=email]"
      assert_select "u-time-zone input[type=hidden][name=time_zone]"
    end
    assert_select "#studio-auth-sign-in a[href=?]", login_path
  end

  test "signing up creates no user until the code checks out, then creates it and signs in" do
    code = sign_up_code(full_name: " New  Cook ", email_address: " New@Studio.com ", time_zone: "America/Toronto")
    assert_not User.exists?(email_address: "new@studio.com")

    assert_difference -> { User.count } => 1, -> { Session.count } => 1 do
      post verify_path, params: {code: code}
    end

    user = User.find_by!(email_address: "new@studio.com")
    assert_equal "New Cook", user.full_name
    assert_redirected_to root_path
    assert_equal 0, Studio::Auth::PendingSignUp.count
  end

  test "an app with setup gets the pending sign-up, and finishing it creates the user and signs in" do
    with_setup do
      code = sign_up_code(full_name: "New Cook", email_address: "new@studio.com", time_zone: "America/Toronto")

      post verify_path, params: {code: code}
      assert_redirected_to "/setup"
      assert_equal 0, User.count
      assert_equal 0, Session.count

      get "/setup"
      assert_equal "new@studio.com New Cook America/Toronto", response.body

      assert_difference -> { User.count } => 1, -> { Session.count } => 1 do
        post "/setup"
      end
      assert_redirected_to root_path
      assert_equal 0, Studio::Auth::PendingSignUp.count

      get "/setup"
      assert_equal "none", response.body
    end
  end

  test "someone who left setup comes back through the sign-in page on another browser" do
    with_setup do
      post verify_path, params: {code: sign_up_code(full_name: "New Cook", email_address: "new@studio.com")}
      reset!

      perform_enqueued_jobs { post login_path, params: {email_address: "new@studio.com"} }
      assert_redirected_to verify_path
      post verify_path, params: {code: mailed_code}

      assert_redirected_to "/setup"
      get "/setup"
      assert_equal "new@studio.com New Cook ", response.body
    end
  end

  test "a browser left on setup loses the sign-up after an hour, and a fresh code brings it back" do
    with_setup do
      post verify_path, params: {code: sign_up_code(full_name: "New Cook", email_address: "new@studio.com")}

      travel Studio::Auth::PendingSignUp::COOKIE_LIFETIME + 1.second
      get "/setup"
      assert_equal "none", response.body

      perform_enqueued_jobs { post login_path, params: {email_address: "new@studio.com"} }
      post verify_path, params: {code: mailed_code}
      get "/setup"
      assert_equal "new@studio.com New Cook ", response.body
    end
  end

  test "signing in to another account clears a pending sign-up from the browser" do
    User.create!(email_address: "cook@studio.com")
    with_setup do
      post verify_path, params: {code: sign_up_code(full_name: "New Cook", email_address: "new@studio.com")}
      perform_enqueued_jobs { post login_path, params: {email_address: "cook@studio.com"} }
      post verify_path, params: {code: mailed_code}

      get "/setup"
      assert_equal "none", response.body
    end
  end

  test "a missing full name re-renders with the error under the field" do
    assert_no_difference -> { Studio::Auth::LoginCode.count } do
      post signup_path, params: {full_name: "  ", email_address: "new@studio.com"}
    end

    assert_response :unprocessable_content
    assert_select "input[name=full_name][aria-invalid=true]"
    assert_select "#studio-auth-full-name-error", text: I18n.t("studio_auth.flash.full_name_missing")
    assert_select "input[name=email_address][value=?]", "new@studio.com"
  end

  test "a full name over the limit is turned away" do
    post signup_path, params: {full_name: "a" * 101, email_address: "new@studio.com"}

    assert_response :unprocessable_content
    assert_select "#studio-auth-full-name-error"
  end

  test "an undeliverable address re-renders with the error under the email field" do
    post signup_path, params: {full_name: "New Cook", email_address: "cook@example.com"}

    assert_response :unprocessable_content
    assert_select "#studio-auth-email-error", text: I18n.t("studio_auth.flash.undeliverable")
  end

  test "signing up with an address that has an account signs that account in" do
    user = User.create!(email_address: "cook@studio.com", full_name: "Cook")

    post verify_path, params: {code: sign_up_code(full_name: "Someone Else", email_address: "cook@studio.com")}

    assert_redirected_to root_path
    assert_equal "Cook", user.reload.full_name
    assert_equal 1, user.sessions.count
    assert_equal 0, Studio::Auth::PendingSignUp.count
  end

  test "a signed-in visitor is sent home from the signup page" do
    sign_in_as(User.create!(email_address: "cook@studio.com"))

    get signup_path

    assert_redirected_to root_path
  end

  test "with sign-up off the signup page sends people to sign in" do
    Studio::Auth.stubs(:sign_up?).returns(false)

    get signup_path

    assert_redirected_to login_path
  end

  private

  def sign_up_code(**params)
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { post signup_path, params: params }
    assert_redirected_to verify_path
    mailed_code
  end

  def mailed_code
    ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
  end

  def with_setup
    ApplicationController.class_eval { def sign_up_setup_path = "/setup" }
    yield
  ensure
    ApplicationController.class_eval { remove_method :sign_up_setup_path }
  end
end
