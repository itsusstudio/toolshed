require "test_helper"

class Studio::Auth::ForControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include AuthenticationTestHelpers

  test "a protected page sends a signed-out visitor to sign in and back afterwards" do
    get "/private"
    assert_redirected_to login_path

    sign_in_with_code("cook@studio.com")
    assert_redirected_to "/private"
  end

  test "a native app request gets 401 instead of a redirect, and is not kept as the return path" do
    ApplicationController.any_instance.stubs(:hotwire_native_app?).returns(true)
    get "/private"
    assert_response :unauthorized
    assert_nil session[Studio::Auth::ForController::RETURN_TO_KEY]
  end

  test "a cookie for a missing session is looked up once per request" do
    sign_in_with_code("cook@studio.com")
    Session.delete_all

    queries = 0
    counter = ->(*, payload) { queries += 1 if payload[:sql].include?("FROM \"sessions\"") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get "/" }

    assert_equal "out out", response.body
    assert_equal 1, queries
  end

  test "a return path never leaves the site" do
    get "//evil.example/x"
    assert_nil session[Studio::Auth::ForController::RETURN_TO_KEY]
  end

  test "code requests are rate limited by IP" do
    10.times { post login_path, params: {email_address: "cook@studio.com"} }

    post login_path, params: {email_address: "cook@studio.com"}
    assert_response :too_many_requests
    assert_select "input[name=email_address][aria-invalid=true][value=?]", "cook@studio.com"
    assert_select "#studio-auth-email-error", text: I18n.t("studio_auth.flash.too_many_requests")
  end

  test "strangers asking for a code from many IPs cannot lock the owner out" do
    sign_in_with_code("cook@studio.com")
    delete logout_path

    attacker = open_session
    20.times { |i| attacker.post login_path, params: {email_address: "cook@studio.com"}, headers: {"REMOTE_ADDR" => "10.0.0.#{i}"} }

    post verify_path, params: {code: request_authentication_code("cook@studio.com")}
    assert_redirected_to root_path
  end

  test "the test helper signs in without a code and signs out" do
    extend Studio::Auth::TestHelper

    sign_in_as(User.create!(email_address: "cook@studio.com"))

    get "/private"
    assert_response :success

    sign_out
    get "/private"
    assert_redirected_to login_path
  end

  test "after_sign_in runs once on a fresh sign-in" do
    signed_in = []
    ApplicationController.define_method(:after_sign_in) { |user| signed_in << user.email_address }

    sign_in_with_code("cook@studio.com")
    assert_equal ["cook@studio.com"], signed_in
  ensure
    ApplicationController.remove_method(:after_sign_in)
  end

  test "a retry after a lost response, from the same browser, still gets a working code" do
    User.create!(email_address: "cook@studio.com")
    first_try = open_session
    first_try.get login_path
    device_cookie = first_try.cookies[Studio::Auth::DeviceCookie::COOKIE_NAME.to_s]
    perform_enqueued_jobs { first_try.post login_path, params: {email_address: "cook@studio.com"} }
    code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]

    retry_after_lost_response = open_session
    retry_after_lost_response.cookies[Studio::Auth::DeviceCookie::COOKIE_NAME.to_s] = device_cookie
    retry_after_lost_response.post login_path, params: {email_address: "cook@studio.com"}
    retry_after_lost_response.post verify_path, params: {code: code}

    assert_equal 1, Studio::Auth::LoginCode.count
    assert_equal root_path, URI(retry_after_lost_response.response.location).path
  end

  test "a code typed in Arabic-Indic digits signs in" do
    User.create!(email_address: "cook@studio.com")
    code = request_authentication_code("cook@studio.com")

    post verify_path, params: {code: code.tr("0123456789", "٠١٢٣٤٥٦٧٨٩")}

    assert_redirected_to root_path
  end

  test "the sign-in page is the gem's Uniform auth shell, inside the app layout, with the app's name as its wordmark" do
    get login_path

    assert_select "body .u-auth-shell main#studio-auth-page"
    assert_select ".u-auth-shell > header a.u-wordmark.u-wordmark-serif", text: "Dummy"
    assert_select ".u-auth-shell > footer a[href=?]", "https://dummy.app/terms"
    assert_select "input.u-input[name=email_address][autocomplete=email]"
  end

  test "sending a new code from the code page mails a fresh one right away and ends the old one" do
    User.create!(email_address: "cook@studio.com")
    old_code = request_authentication_code("cook@studio.com")
    get verify_path

    assert_select "form#studio-auth-resend-form[action=?] input[name=email_address][value=?]", login_path, "cook@studio.com"
    assert_select "form#studio-auth-resend-form input[name=resend]"

    travel Studio::Auth::SignInLimits::RESEND_COOLDOWN + 1.second
    perform_enqueued_jobs { post login_path, params: {email_address: "cook@studio.com", resend: "1"} }
    assert_redirected_to verify_path
    new_code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]

    post verify_path, params: {code: old_code}
    assert_response :unprocessable_content
    post verify_path, params: {code: new_code}
    assert_redirected_to root_path
  end

  test "sending a new code right after the last one waits, and mails nothing" do
    User.create!(email_address: "cook@studio.com")
    request_authentication_code("cook@studio.com")

    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      perform_enqueued_jobs { post login_path, params: {email_address: "cook@studio.com", resend: "1"} }
    end

    assert_redirected_to verify_path
    follow_redirect!
    assert_select "[role=alert]", text: I18n.t("studio_auth.flash.resend_too_soon")
  end

  test "sending a new code works for an address that is signing up" do
    post "/signup_code", params: {email_address: "new@studio.com"}
    travel Studio::Auth::SignInLimits::RESEND_COOLDOWN + 1.second

    assert_difference -> { Studio::Auth::LoginCode.count }, 1 do
      post login_path, params: {email_address: "new@studio.com", resend: "1"}
    end
    assert_redirected_to verify_path
  end

  test "the resend flag counts only for the address this browser is verifying" do
    User.create!(email_address: "cook@studio.com")
    post login_path, params: {email_address: "cook@studio.com"}

    assert_no_difference -> { Studio::Auth::LoginCode.count } do
      post login_path, params: {email_address: "stranger@studio.com", resend: "1"}
    end
    assert_redirected_to login_path
  end

  test "an address with no account gets the new-account page, which offers sign-up or another address" do
    assert_no_difference -> { Studio::Auth::LoginCode.count } do
      post login_path, params: {email_address: "Nobody@Studio.com"}
    end
    assert_redirected_to login_path
    follow_redirect!

    assert_select "#studio-auth-no-account-email", text: /nobody@studio\.com/
    assert_select "a#studio-auth-no-account-create[href=?]", signup_path
    assert_select "a#studio-auth-no-account-change[href=?]", login_path
  end

  test "using a different address from the new-account page prefills the typed one to fix" do
    post login_path, params: {email_address: "nobody@studio.com"}
    follow_redirect!

    get login_path

    assert_select "input[name=email_address][value=?]", "nobody@studio.com"
    assert_select ".u-field #studio-auth-sign-up a[href=?]", signup_path
  end

  test "the signup form can prefill the address typed on the sign-in page, for a while" do
    post login_path, params: {email_address: "nobody@studio.com"}

    get "/signup_typed"
    assert_equal "nobody@studio.com", response.body

    travel Studio::Auth::ForController::VERIFIED_EMAIL_TTL + 1.second do
      get "/signup_typed"
      assert_equal "", response.body
    end
  end

  test "without sign-up an address with no account gets an error under the field" do
    Studio::Auth.stubs(:sign_up?).returns(false)

    post login_path, params: {email_address: "nobody@studio.com"}

    assert_response :unprocessable_content
    assert_select "input[name=email_address][value=?][aria-invalid=true]", "nobody@studio.com"
    assert_select "#studio-auth-email-error", text: I18n.t("studio_auth.flash.no_account")
    assert_select "#studio-auth-sign-up", count: 0
  end

  test "going back to change the address prefills it without putting it in the URL" do
    User.create!(email_address: "cook@studio.com")
    post login_path, params: {email_address: "cook@studio.com"}
    get verify_path
    assert_select "a#studio-auth-start-over[href=?]", login_path

    get login_path
    assert_select "input[name=email_address][value=?]", "cook@studio.com"
  end

  test "too many wrong codes sends you back to sign in with the error under the prefilled field" do
    User.create!(email_address: "cook@studio.com")
    post login_path, params: {email_address: "cook@studio.com"}

    Studio::Auth::LoginCode::MAX_ATTEMPTS.times { post verify_path, params: {code: "000000"} }
    assert_redirected_to login_path
    follow_redirect!

    assert_select "input[name=email_address][value=?][aria-invalid=true]", "cook@studio.com"
    assert_select "#studio-auth-email-error", text: I18n.t("studio_auth.flash.too_many_attempts")
    assert_select "#studio-auth-alert", count: 0
  end

  test "a wrong code shows its error under the field, not as a banner" do
    User.create!(email_address: "cook@studio.com")
    post login_path, params: {email_address: "cook@studio.com"}

    post verify_path, params: {code: "000000"}

    assert_response :unprocessable_content
    assert_select "input[name=code][aria-invalid=true][aria-describedby=studio-auth-code-error]"
    assert_select "#studio-auth-code-error", text: I18n.t("studio_auth.flash.wrong_code")
    assert_select "#studio-auth-alert", count: 0
  end

  test "an address typed on an Arabic keyboard gets a real code" do
    user = User.create!(email_address: "cook12@studio.com")

    post login_path, params: {email_address: "\u200Fcook١٢＠studio.com"}

    assert_redirected_to verify_path
    assert_equal user.email_address, Studio::Auth::LoginCode.last.email_address
  end

  test "a rejected address re-renders with the typed value and an error under the field" do
    post login_path, params: {email_address: "cook@example.com"}

    assert_response :unprocessable_content
    assert_select "input[name=email_address][value=?][aria-invalid=true]", "cook@example.com"
    assert_select "#studio-auth-email-error", text: I18n.t("studio_auth.flash.undeliverable")
  end

  test "start_sign_in_for sends an old undeliverable address back to login instead of crashing" do
    User.new(email_address: "old@example.com").save!(validate: false)
    post "/signup", params: {email_address: "old@example.com"}

    assert_redirected_to login_path
    assert_equal I18n.t("studio_auth.flash.undeliverable"), flash[:alert]
  end

  test "start_sign_up_for mails a code and creates the account only once the code is right" do
    perform_enqueued_jobs { post "/signup_code", params: {email_address: " New@Studio.com "} }

    assert_redirected_to verify_path
    assert_not User.exists?(email_address: "new@studio.com")
    code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]

    post verify_path, params: {code: code}

    assert_response :see_other
    assert_equal 1, User.find_by!(email_address: "new@studio.com").sessions.count
  end

  test "a right sign-up code with nothing to create sends the visitor back to login" do
    ApplicationController.any_instance.stubs(:create_account_for).returns(nil)
    perform_enqueued_jobs { post "/signup_code", params: {email_address: "new@studio.com"} }
    code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]

    post verify_path, params: {code: code}

    assert_redirected_to login_path
    assert_equal 0, Session.count
  end

  test "create_account_for can redirect instead, and the code is spent" do
    ApplicationController.class_eval { def create_account_for(email_address) = redirect_to("/finish") }
    perform_enqueued_jobs { post "/signup_code", params: {email_address: "new@studio.com"} }
    code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]

    post verify_path, params: {code: code}

    assert_redirected_to "/finish"
    assert_equal 0, Session.count
  ensure
    ApplicationController.class_eval { def create_account_for(email_address) = User.create!(email_address: email_address) }
  end

  test "#create_account_for sends a verified sign-up to the signup form, keeping the address out of the URL" do
    ApplicationController.class_eval { remove_method :create_account_for }
    perform_enqueued_jobs { post "/signup_code", params: {email_address: "new@studio.com"} }
    code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]

    post verify_path, params: {code: code}

    assert_redirected_to signup_path
    assert_equal 0, Session.count
  ensure
    ApplicationController.class_eval { def create_account_for(email_address) = User.create!(email_address: email_address) }
  end

  test "#verified_email_address holds the address a sign-up code proved, for 30 minutes" do
    ApplicationController.class_eval { remove_method :create_account_for }
    perform_enqueued_jobs { post "/signup_code", params: {email_address: "new@studio.com"} }
    code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
    post verify_path, params: {code: code}

    get "/signup_verified", params: {email_address: " New@Studio.com "}
    assert_equal "true new@studio.com", response.body

    get "/signup_verified", params: {email_address: "other@studio.com"}
    assert_equal "false new@studio.com", response.body

    travel 31.minutes do
      get "/signup_verified", params: {email_address: "new@studio.com"}
      assert_equal "false ", response.body
    end
  ensure
    ApplicationController.class_eval { def create_account_for(email_address) = User.create!(email_address: email_address) }
  end

  test "#verified_email_address? is false for a browser that never entered a sign-up code" do
    get "/signup_verified", params: {email_address: "new@studio.com"}

    assert_equal "false ", response.body
  end

  test "sign out everywhere ends every session, forgets known devices and cancels codes waiting to be typed" do
    sign_in_with_code("cook@studio.com")
    User.first.sessions.create!
    other_browser = Studio::Auth::DeviceCookie.new(ActionDispatch::TestRequest.create.cookie_jar)
    waiting = Studio::Auth::RequestCode.call(email_address: "cook@studio.com", device_cookie: other_browser,
      ip_address: "6.6.6.6", user_agent: "other")

    delete logout_everywhere_path

    assert_equal 0, Session.count
    assert_equal 0, Studio::Auth::KnownDevice.count
    assert_equal :expired, Studio::Auth::VerifyCode.call(id: waiting.id, code: waiting.code).status
  end

  test "signing out disconnects that session's sockets and leaves the user's other devices connected" do
    sign_in_with_code("cook@studio.com")
    current = Session.last
    other = User.first.sessions.create!

    delete logout_path

    assert_equal 1, cable_disconnects(current)
    assert_equal 0, cable_disconnects(other)
  end

  test "signing out everywhere disconnects every session's sockets" do
    sign_in_with_code("cook@studio.com")
    sessions = [Session.last, User.first.sessions.create!]

    delete logout_everywhere_path

    assert_equal [1, 1], sessions.map { cable_disconnects(it) }
  end

  test "signing in again in the same browser ends its previous session" do
    sign_in_with_code("cook@studio.com")
    previous = Session.last

    sign_in_with_code("cook@studio.com")

    refute Session.exists?(previous.id)
  end

  test "a session stops working once the app says the account cannot sign in" do
    sign_in_with_code("cook@studio.com")
    User.any_instance.stubs(:can_sign_in?).returns(false)

    get "/private"
    assert_redirected_to login_path
  end

  test "the code page shows the dev code only in development" do
    User.create!(email_address: "cook@studio.com")
    post login_path, params: {email_address: "cook@studio.com"}
    follow_redirect!
    assert_select "#studio-auth-dev-code", false

    Studio::Auth::PendingLoginCode.stubs(:include_dev_code?).returns(true)
    User.create!(email_address: "other@studio.com")
    post login_path, params: {email_address: "other@studio.com"}
    follow_redirect!
    assert_select "#studio-auth-dev-code"
  end

  test "IPv6 addresses in one /64 share a rate limit" do
    assert_equal rate_limit_key_for("2001:db8:1:2::1"), rate_limit_key_for("2001:db8:1:2:ffff::9")
    refute_equal rate_limit_key_for("2001:db8:1:2::1"), rate_limit_key_for("2001:db8:1:3::1")
    assert_equal "203.0.113.7", rate_limit_key_for("203.0.113.7")
  end

  private

  def cable_disconnects(session)
    ActionCable.server.pubsub.broadcasts("action_cable/#{session.to_gid_param}").size
  end

  def rate_limit_key_for(ip_address)
    controller = Studio::Auth::BaseController.new
    controller.request = ActionDispatch::TestRequest.create("REMOTE_ADDR" => ip_address)
    controller.send(:rate_limit_key)
  end

  def request_authentication_code(email_address)
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { post login_path, params: {email_address: email_address} }
    ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
  end
end
