require "test_helper"

class Studio::Auth::LoginCodeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  LoginCode = Studio::Auth::LoginCode

  setup do
    @user = User.create!(email_address: "cook@studio.com")
    @device = Studio::Auth::DeviceCookie.new(ActionDispatch::TestRequest.create.cookie_jar)
  end

  test "an address with no account gets a real code that verifies to no user" do
    issued = nil
    assert_enqueued_jobs 1 do
      issued = request_sign_in("new@studio.com")
    end

    result = verify(issued)
    assert_equal :verified, result.status
    assert_nil result.user
    assert_equal "new@studio.com", result.email_address
    assert_not User.exists?(email_address: "new@studio.com")
  end

  test "an address with an account verifies to that user" do
    assert_equal @user, verify(request_sign_in("Cook@Studio.com")).user
  end

  test "the same browser asking again inside the cooldown gets its code back" do
    first = request_sign_in("cook@studio.com")
    second = request_sign_in("cook@studio.com")

    assert_equal first.id, second.id
    assert_nil second.code
    assert_equal 1, LoginCode.count
  end

  test "another browser inside the cooldown is turned away and cannot touch the first code" do
    victim = request_sign_in("cook@studio.com")

    assert_equal :too_many_requests, request_sign_in("cook@studio.com", device_cookie: stranger)
    assert_equal :verified, verify(victim).status
  end

  test "a known device inside the cooldown gets a real code" do
    @device.trust_for(@user, user_agent: "test", ip_address: "1.2.3.4")
    first = request_sign_in("cook@studio.com", device_cookie: Studio::Auth::DeviceCookie.new(ActionDispatch::TestRequest.create.cookie_jar))
    second = request_sign_in("cook@studio.com")

    assert_equal :expired, verify(first).status
    assert_equal :verified, verify(second).status
  end

  test "past the hourly mail budget an unknown device is turned away" do
    LoginCode::MAIL_BUDGET.times do
      request_sign_in("cook@studio.com", device_cookie: stranger)
      travel Studio::Auth::LoginCode::RESEND_INTERVAL + 1.second
    end

    assert_equal :too_many_requests, request_sign_in("cook@studio.com", device_cookie: stranger)
  end

  test "a new code expires the previous one" do
    first = request_sign_in("cook@studio.com")
    travel Studio::Auth::LoginCode::RESEND_INTERVAL + 1.second
    second = request_sign_in("cook@studio.com")

    assert_equal :expired, verify(first).status
    assert_equal :verified, verify(second).status
  end

  test "verify refuses an expired code" do
    issued = request_sign_in("cook@studio.com")

    travel Studio::Auth::LoginCode::TTL + 1.second
    assert_equal :expired, verify(issued).status
  end

  test "failures across codes lock the account and mail its owner once" do
    lock_account
    assert @user.sign_in_locked?

    travel Studio::Auth::LoginCode::LOCKOUT_DURATION + 1.minute
    verify(issue_to("cook@studio.com"), code: "000000x")

    assert_equal 1, enqueued_jobs.count { |job| job["arguments"][1] == "locked" }
  end

  test "each failure past the limit lengthens the lock" do
    lock_account
    travel Studio::Auth::LoginCode::LOCKOUT_DURATION + 1.minute
    refute @user.sign_in_locked?

    verify(issue_to("cook@studio.com"), code: "000000x")
    travel Studio::Auth::LoginCode::LOCKOUT_DURATION + 1.minute
    assert @user.sign_in_locked?, "the 11th failure should lock for two durations"
  end

  test "a locked address is turned away on an unknown device, with or without an account" do
    lock_account
    lock_account("nobody@studio.com")

    assert_equal :too_many_requests, request_sign_in("cook@studio.com")
    assert_equal :too_many_requests, request_sign_in("nobody@studio.com")
  end

  test "an app review account gets its fixed code" do
    with_app_review_accounts({"Review@Studio.com": "381904"}) do
      User.create!(email_address: "review@studio.com")

      issued = request_sign_in("review@studio.com")
      assert_equal "381904", issued.code
      assert_equal :verified, verify(issued).status
    end
  end

  test "wrong codes never lock an app review account or turn its requests away" do
    with_app_review_accounts({"review@studio.com": "381904"}) do
      reviewer = User.create!(email_address: "review@studio.com")
      events = capture_event_names do
        3.times do
          issued = request_sign_in("review@studio.com", device_cookie: stranger)
          Studio::Auth::LoginCode::MAX_ATTEMPTS.times { verify(issued, code: "000000") }
          travel Studio::Auth::LoginCode::RESEND_INTERVAL + 1.second
        end
      end

      refute reviewer.sign_in_locked?
      assert_includes events, "authentication.app_review_account_code_rejected"
      request_sign_in("review@studio.com", device_cookie: stranger)
      second_device = request_sign_in("review@studio.com", device_cookie: stranger)
      assert_equal :verified, verify(second_device).status
    end
  end

  test "a device unused past the session lifetime stops skipping the lockout" do
    @device.trust_for(@user, user_agent: "test", ip_address: "1.2.3.4")

    travel Studio::Auth::KnownDevice::TRUST_PERIOD + 1.day
    refute @device.trusted_for?(@user)
  end

  test "a stolen known-device cookie locks after its own failures, while the owner's other devices still sign in" do
    owner_laptop = stranger
    owner_laptop.trust_for(@user, user_agent: "laptop", ip_address: "1.2.3.4")
    @device.trust_for(@user, user_agent: "stolen", ip_address: "1.2.3.4")

    (Studio::Auth::LoginCode::LOCKOUT_WRONG_CODES / Studio::Auth::LoginCode::MAX_ATTEMPTS).times do
      issued = request_sign_in("cook@studio.com")
      Studio::Auth::LoginCode::MAX_ATTEMPTS.times { verify(issued, code: "000000x") }
    end

    assert_equal :too_many_requests, request_sign_in("cook@studio.com")
    assert_equal :verified, verify(request_sign_in("cook@studio.com", device_cookie: owner_laptop)).status
  end

  test "real and unknown addresses run the same number of queries" do
    request_sign_in("warm@studio.com")
    real = count_queries { request_sign_in("cook@studio.com", device_cookie: stranger) }
    unknown = count_queries { request_sign_in("nobody@studio.com", device_cookie: stranger) }
    assert_equal real, unknown

    travel Studio::Auth::LoginCode::RESEND_INTERVAL + 1.second
    real_code = request_sign_in("cook@studio.com", device_cookie: stranger)
    unknown_code = request_sign_in("nobody@studio.com", device_cookie: stranger)
    assert_equal count_queries { verify(real_code, code: "000000x") }, count_queries { verify(unknown_code, code: "000000x") }
  end

  test "an account the app says cannot sign in gets no mail, and its codes stop working" do
    issued = request_sign_in("cook@studio.com")
    User.any_instance.stubs(:can_sign_in?).returns(false)

    assert_equal :invalid, verify(issued).status
    travel Studio::Auth::LoginCode::RESEND_INTERVAL + 1.second
    perform_enqueued_jobs { request_sign_in("cook@studio.com") }
    assert_empty ActionMailer::Base.deliveries
  end

  test "an app review account locks after its daily cap of wrong codes, with an event and no mail" do
    with_app_review_accounts({"review@studio.com": "381904"}) do
      reviewer = User.create!(email_address: "review@studio.com")
      events = capture_event_names do
        perform_enqueued_jobs do
          (Studio::Auth::LoginCode::APP_REVIEW_LOCKOUT_WRONG_CODES / Studio::Auth::LoginCode::MAX_ATTEMPTS).times do
            issued = request_sign_in("review@studio.com", device_cookie: stranger)
            Studio::Auth::LoginCode::MAX_ATTEMPTS.times { verify(issued, code: "000000") }
          end
        end
      end

      assert reviewer.sign_in_locked?
      assert_includes events, "authentication.app_review_account_locked"
      assert_empty ActionMailer::Base.deliveries
      assert_equal :too_many_requests, request_sign_in("review@studio.com", device_cookie: stranger)
    end
  end

  test "the per-IP hourly limit is counted in the database" do
    Studio::Auth::LoginCode::IP_HOURLY_LIMIT.times { |n| request_sign_in("visitor#{n}@studio.com", device_cookie: stranger) }

    assert_equal :too_many_requests, request_sign_in("cook@studio.com")
  end

  test "signing in on a new device replaces its cookie, so a planted one never becomes known" do
    @device.ensure_device_token!
    planted = @device.device_token

    @device.trust_for(@user, user_agent: "test", ip_address: "1.2.3.4")

    refute_equal planted, @device.device_token
    assert @device.trusted_for?(@user)
  end

  private

  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 if !payload[:name].to_s.include?("SCHEMA") && payload[:sql] !~ /\A(BEGIN|COMMIT|SAVEPOINT|RELEASE|ROLLBACK)/ }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  def request_sign_in(email_address, device_cookie: @device)
    LoginCode.request_for(email_address: email_address, device_cookie: device_cookie, ip_address: "1.2.3.4", user_agent: "test")
  end

  def issue_to(email_address)
    LoginCode.send(:issue, email_address: email_address, known_device: false, device_cookie: stranger, ip_address: "6.6.6.6", user_agent: "attacker")
  end

  def stranger
    Studio::Auth::DeviceCookie.new(ActionDispatch::TestRequest.create.cookie_jar)
  end

  def verify(issued, code: issued.code)
    LoginCode.verify(id: issued.id, code: code)
  end

  def lock_account(email_address = "cook@studio.com")
    (Studio::Auth::LoginCode::LOCKOUT_WRONG_CODES / Studio::Auth::LoginCode::MAX_ATTEMPTS).times do
      issued = issue_to(email_address)
      Studio::Auth::LoginCode::MAX_ATTEMPTS.times { verify(issued, code: "000000x") }
      travel Studio::Auth::LoginCode::RESEND_INTERVAL + 1.second
    end
  end

  def capture_event_names
    names = []
    subscriber = Object.new
    subscriber.define_singleton_method(:emit) { |event| names << event[:name] }
    Rails.event.subscribe(subscriber)
    yield
    names
  ensure
    Rails.event.unsubscribe(subscriber)
  end

  def with_app_review_accounts(entries)
    Rails.application.credentials.stubs(:dig).with(:studio_auth, :app_review_accounts).returns(entries)
    yield
  end
end
