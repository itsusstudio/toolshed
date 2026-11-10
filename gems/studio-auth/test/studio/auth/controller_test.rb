require "test_helper"

class Studio::Auth::ControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include AuthenticationTestHelpers

  test "a protected page sends a signed-out visitor to sign in and back afterwards" do
    get "/private"
    assert_redirected_to login_path

    sign_in_as("cook@studio.com")
    assert_redirected_to "/private"
  end

  test "a native app request gets 401 instead of a redirect" do
    ApplicationController.any_instance.stubs(:hotwire_native_app?).returns(true)
    get "/private"
    assert_response :unauthorized
  end

  test "a cookie for a missing session is looked up once per request" do
    sign_in_as("cook@studio.com")
    Session.delete_all

    queries = 0
    counter = ->(*, payload) { queries += 1 if payload[:sql].include?("FROM \"sessions\"") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get "/" }

    assert_equal "out out", response.body
    assert_equal 1, queries
  end

  test "a first device sends no mail and a second device does" do
    perform_enqueued_jobs { sign_in_as("cook@studio.com") }
    assert_equal 0, new_device_mails.size

    other_device = open_session
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { other_device.post login_path, params: {email_address: "cook@studio.com"} }
    code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
    perform_enqueued_jobs { other_device.post verify_path, params: {code: code} }

    assert_equal 1, new_device_mails.size
    assert_includes new_device_mails.first.text_part.body.to_s, "support@dummy.app"
  end

  test "a sensitive page asks for a fresh code after the window and comes back" do
    sign_in_as("cook@studio.com")
    get "/danger"
    assert_response :success

    travel Studio::Auth::REAUTHENTICATION_WINDOW + 1.minute
    get "/danger"
    assert_redirected_to reauthentication_path

    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { post reauthentication_path }
    code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
    post reauthentication_verify_path, params: {code: code}
    assert_redirected_to "/danger"

    get "/danger"
    assert_response :success
  end

  test "a non-GET sensitive action returns to the same-origin page it came from" do
    sign_in_as("cook@studio.com")
    travel Studio::Auth::REAUTHENTICATION_WINDOW + 1.minute

    delete "/danger", headers: {"Referer" => "http://www.example.com/private"}
    assert_redirected_to reauthentication_path
    assert_equal "/private", session[Studio::Auth::Controller::RETURN_TO_KEY]

    delete "/danger", headers: {"Referer" => "https://evil.example/phish"}
    assert_nil session[Studio::Auth::Controller::RETURN_TO_KEY]
  end

  test "a return path never leaves the site" do
    get "//evil.example/x"
    assert_nil session[Studio::Auth::Controller::RETURN_TO_KEY]
  end

  test "code requests are rate limited by IP" do
    10.times { post login_path, params: {email_address: "cook@studio.com"} }

    post login_path, params: {email_address: "cook@studio.com"}
    assert_response :too_many_requests
  end

  test "strangers asking for a code from many IPs cannot lock the owner out" do
    sign_in_as("cook@studio.com")
    delete logout_path

    attacker = open_session
    20.times { |i| attacker.post login_path, params: {email_address: "cook@studio.com"}, headers: {"REMOTE_ADDR" => "10.0.0.#{i}"} }

    post verify_path, params: {code: request_authentication_code("cook@studio.com")}
    assert_redirected_to root_path
  end

  test "after_sign_in runs once on a fresh sign-in" do
    signed_in = []
    ApplicationController.define_method(:after_sign_in) { |user| signed_in << user.email_address }

    sign_in_as("cook@studio.com")
    assert_equal ["cook@studio.com"], signed_in
  ensure
    ApplicationController.remove_method(:after_sign_in)
  end

  test "a retry after a lost response, from the same browser, still gets a working code" do
    User.create!(email_address: "cook@studio.com")
    first_try = open_session
    first_try.get login_path
    device_cookie = first_try.cookies["studio_device"]
    perform_enqueued_jobs { first_try.post login_path, params: {email_address: "cook@studio.com"} }
    code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]

    retry_after_lost_response = open_session
    retry_after_lost_response.cookies["studio_device"] = device_cookie
    retry_after_lost_response.post login_path, params: {email_address: "cook@studio.com"}
    retry_after_lost_response.post verify_path, params: {code: code}

    assert_equal 1, Studio::Auth::LoginChallenge.count
    assert_equal root_path, URI(retry_after_lost_response.response.location).path
  end

  test "a code typed in Arabic-Indic digits signs in" do
    User.create!(email_address: "cook@studio.com")
    code = request_authentication_code("cook@studio.com")

    post verify_path, params: {code: code.tr("0123456789", "٠١٢٣٤٥٦٧٨٩")}

    assert_redirected_to root_path
  end

  test "an address typed on an Arabic keyboard reaches a real challenge" do
    user = User.create!(email_address: "cook12@studio.com")

    post login_path, params: {email_address: "\u200Fcook١٢＠studio.com"}

    assert_redirected_to verify_path
    assert_equal user.id, Studio::Auth::LoginChallenge.last.user_id
  end

  test "a rejected address re-renders with the typed value and an error under the field" do
    post login_path, params: {email_address: "cook@example.com"}

    assert_response :unprocessable_content
    assert_select "input[name=email_address][value=?][aria-invalid=true]", "cook@example.com"
    assert_select "#studio-auth-email-error", text: I18n.t("studio_auth.flash.undeliverable")
  end

  test "start_sign_in_for sends an undeliverable address back to login instead of crashing" do
    post "/signup", params: {email_address: "new@example.com"}

    assert_redirected_to login_path
    assert_equal I18n.t("studio_auth.flash.undeliverable"), flash[:alert]
  end

  test "sign out everywhere ends every session and forgets known devices" do
    sign_in_as("cook@studio.com")
    User.first.sessions.create!

    delete logout_everywhere_path

    assert_equal 0, Session.count
    assert_equal 0, Studio::Auth::KnownDevice.count
  end

  test "sign out everywhere also cancels codes waiting to be typed" do
    sign_in_as("cook@studio.com")
    waiting = Studio::Auth::Challenges.request_sign_in(email_address: "cook@studio.com", device: Studio::Auth::Device.new(ActionDispatch::TestRequest.create.cookie_jar), ip_address: "6.6.6.6", user_agent: "other")

    delete logout_everywhere_path

    assert_equal :expired, Studio::Auth::Challenges.verify(id: waiting.id, code: waiting.code, purpose: "sign_in").status
  end

  test "signing in again in the same browser ends its previous session" do
    sign_in_as("cook@studio.com")
    previous = Session.last

    sign_in_as("cook@studio.com")

    refute Session.exists?(previous.id)
  end

  test "a session stops working once the app says the account cannot sign in" do
    sign_in_as("cook@studio.com")
    User.any_instance.stubs(:can_sign_in?).returns(false)

    get "/private"
    assert_redirected_to login_path
  end

  test "the code page shows the dev code only in development" do
    User.create!(email_address: "cook@studio.com")
    post login_path, params: {email_address: "cook@studio.com"}
    follow_redirect!
    assert_select "#studio-auth-dev-code", false

    Studio::Auth.stubs(:dev_environment?).returns(true)
    post login_path, params: {email_address: "other@studio.com"}
    follow_redirect!
    assert_select "#studio-auth-dev-code"
  end

  private

  def new_device_mails
    ActionMailer::Base.deliveries.select { |mail| mail.subject == "New sign-in to Dummy" }
  end

  def request_authentication_code(email_address)
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { post login_path, params: {email_address: email_address} }
    ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
  end
end
