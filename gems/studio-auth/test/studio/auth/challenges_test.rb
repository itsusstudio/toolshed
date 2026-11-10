require "test_helper"

class Studio::Auth::ChallengesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  Challenges = Studio::Auth::Challenges
  LoginChallenge = Studio::Auth::LoginChallenge

  setup do
    @user = User.create!(email_address: "cook@studio.com")
    @device = Studio::Auth::Device.new(ActionDispatch::TestRequest.create.cookie_jar)
  end

  test "request_sign_in refuses an address that cannot receive mail" do
    assert_equal :undeliverable, request_sign_in("cook@example.com")
    assert_equal :undeliverable, request_sign_in("not an email")
    assert_equal 0, LoginChallenge.count
  end

  test "an unknown address gets a decoy that enqueues mail like a real one and never verifies" do
    issued = nil
    assert_enqueued_jobs 1 do
      issued = request_sign_in("nobody@studio.com")
    end

    assert LoginChallenge.find(issued.id).decoy?
    assert_equal :invalid, verify(issued).status
  end

  test "the same browser asking again inside the cooldown gets its challenge back" do
    first = request_sign_in("cook@studio.com")
    second = request_sign_in("cook@studio.com")

    assert_equal first.id, second.id
    assert_nil second.code
    assert_equal 1, LoginChallenge.count
  end

  test "another browser inside the cooldown gets a decoy and cannot touch the first challenge" do
    victim = request_sign_in("cook@studio.com")
    attacker = request_sign_in("cook@studio.com", device: stranger)

    refute_equal victim.id, attacker.id
    assert LoginChallenge.find(attacker.id).decoy?
    Studio::Auth::CODE_MAX_ATTEMPTS.times { verify(attacker, code: "000000x") }
    assert_equal :verified, verify(victim).status
  end

  test "a known device inside the cooldown gets a real challenge" do
    @device.remember_for(@user, user_agent: "test", ip_address: "1.2.3.4")
    first = request_sign_in("cook@studio.com", device: Studio::Auth::Device.new(ActionDispatch::TestRequest.create.cookie_jar))
    second = request_sign_in("cook@studio.com")

    refute LoginChallenge.find(second.id).decoy?
    assert_equal :expired, verify(first).status
    assert_equal :verified, verify(second).status
  end

  test "past the hourly mail budget an unknown device gets decoys" do
    Challenges::MAIL_BUDGET.times do
      request_sign_in("cook@studio.com", device: stranger)
      travel Studio::Auth::CODE_RESEND_INTERVAL + 1.second
    end

    assert LoginChallenge.find(request_sign_in("cook@studio.com", device: stranger).id).decoy?
  end

  test "a new challenge expires the previous one" do
    first = request_sign_in("cook@studio.com")
    travel Studio::Auth::CODE_RESEND_INTERVAL + 1.second
    second = request_sign_in("cook@studio.com")

    assert_equal :expired, verify(first).status
    assert_equal :verified, verify(second).status
  end

  test "verify accepts a code once" do
    issued = request_sign_in("cook@studio.com")

    result = verify(issued)
    assert_equal :verified, result.status
    assert_equal @user, result.user
    assert_equal :expired, verify(issued).status
  end

  test "verify refuses an expired code" do
    issued = request_sign_in("cook@studio.com")

    travel Studio::Auth::CODE_TTL + 1.second
    assert_equal :expired, verify(issued).status
  end

  test "verify ends the challenge after the attempt limit, even for the right code" do
    issued = request_sign_in("cook@studio.com")
    (Studio::Auth::CODE_MAX_ATTEMPTS - 1).times { assert_equal :invalid, verify(issued, code: "000000x").status }

    assert_equal :too_many_attempts, verify(issued, code: "000000x").status
    assert_equal :too_many_attempts, verify(issued).status
  end

  test "verify binds a reauthentication challenge to its user" do
    other = User.create!(email_address: "other@studio.com")
    issued = Challenges.request_reauthentication(user: @user, device: @device, ip_address: "1.2.3.4", user_agent: "test")

    assert_equal :expired, Challenges.verify(id: issued.id, code: issued.code, purpose: "reauthentication", user: other).status
    assert_equal :expired, Challenges.verify(id: issued.id, code: issued.code, purpose: "sign_in").status
    assert_equal :verified, Challenges.verify(id: issued.id, code: issued.code, purpose: "reauthentication", user: @user).status
  end

  test "failures across challenges lock the account and mail its owner once" do
    lock_account
    assert Studio::Auth::Lockout.locked?(@user)

    travel Studio::Auth::LOCK_DURATION + 1.minute
    issued = Challenges.send(:issue, user: @user, purpose: "sign_in", known_device: false, device: stranger, ip_address: "6.6.6.6", user_agent: "attacker")
    verify(issued, code: "000000x")

    assert_equal 1, enqueued_jobs.count { |job| job["arguments"][1] == "locked" }
  end

  test "each failure past the limit lengthens the lock" do
    lock_account
    travel Studio::Auth::LOCK_DURATION + 1.minute
    refute Studio::Auth::Lockout.locked?(@user)

    issued = Challenges.send(:issue, user: @user, purpose: "sign_in", known_device: false, device: stranger, ip_address: "6.6.6.6", user_agent: "attacker")
    verify(issued, code: "000000x")
    travel Studio::Auth::LOCK_DURATION + 1.minute
    assert Studio::Auth::Lockout.locked?(@user), "the 11th failure should lock for two durations"
  end

  test "a locked account gets a decoy from an unknown device" do
    lock_account

    issued = request_sign_in("cook@studio.com")
    assert LoginChallenge.find(issued.id).decoy?
  end

  test "a locked account still signs in from a known device" do
    @device.remember_for(@user, user_agent: "test", ip_address: "1.2.3.4")
    lock_account

    issued = request_sign_in("cook@studio.com")
    assert_equal :verified, verify(issued).status
  end

  test "a review account gets its fixed code, for sign-in and reauthentication" do
    with_review_accounts([{email_address: "Review@Studio.com", login_code: "381904"}]) do
      reviewer = User.create!(email_address: "review@studio.com")

      issued = request_sign_in("review@studio.com")
      assert_equal "381904", issued.code
      assert_equal :verified, verify(issued).status

      reauth = Challenges.request_reauthentication(user: reviewer, device: stranger, ip_address: "1.2.3.4", user_agent: "test")
      assert_equal :verified, Challenges.verify(id: reauth.id, code: "381904", purpose: "reauthentication", user: reviewer).status
    end
  end

  test "wrong codes never lock a review account or turn its requests into decoys" do
    with_review_accounts([{email_address: "review@studio.com", login_code: "381904"}]) do
      reviewer = User.create!(email_address: "review@studio.com")
      events = capture_event_names do
        3.times do
          issued = request_sign_in("review@studio.com", device: stranger)
          Studio::Auth::CODE_MAX_ATTEMPTS.times { verify(issued, code: "000000") }
          travel Studio::Auth::CODE_RESEND_INTERVAL + 1.second
        end
      end

      refute Studio::Auth::Lockout.locked?(reviewer)
      assert_includes events, "authentication.review_account_code_rejected"
      request_sign_in("review@studio.com", device: stranger)
      second_device = request_sign_in("review@studio.com", device: stranger)
      refute LoginChallenge.find(second_device.id).decoy?
      assert_equal :verified, verify(second_device).status
    end
  end

  test "reauthentication from an unknown device is blocked while the account is locked" do
    lock_account

    issued = Challenges.request_reauthentication(user: @user, device: stranger, ip_address: "6.6.6.6", user_agent: "attacker")
    assert_equal :invalid, Challenges.verify(id: issued.id, code: issued.code, purpose: "reauthentication", user: @user).status
  end

  test "reauthentication from a known device still works while the account is locked" do
    @device.remember_for(@user, user_agent: "test", ip_address: "1.2.3.4")
    lock_account

    issued = Challenges.request_reauthentication(user: @user, device: @device, ip_address: "1.2.3.4", user_agent: "test")
    assert_equal :verified, Challenges.verify(id: issued.id, code: issued.code, purpose: "reauthentication", user: @user).status
  end

  test "sign-in keeps working after a development reload replaces the User class" do
    original = ::User
    Object.send(:remove_const, :User)
    Object.const_set(:User, Class.new(ApplicationRecord))
    ::User.include(Studio::Auth::User)
    reloaded = ::User.find(@user.id)

    issued = request_sign_in("cook@studio.com")
    result = verify(issued)

    assert_instance_of ::User, result.user
    assert_equal reloaded, result.user
    assert_equal :first, @device.remember_for(reloaded, user_agent: "test", ip_address: "1.2.3.4")
    assert_equal reloaded, Studio::Auth::KnownDevice.last.user
  ensure
    Object.send(:remove_const, :User)
    Object.const_set(:User, original)
  end

  test "a device unused past the session lifetime stops skipping the lockout" do
    @device.remember_for(@user, user_agent: "test", ip_address: "1.2.3.4")

    travel Studio::Auth::SESSION_ABSOLUTE_TIMEOUT + 1.day
    refute @device.known_for?(@user)
  end

  test "a stolen known-device cookie locks after its own failures, while the owner's other devices still sign in" do
    owner_laptop = stranger
    owner_laptop.remember_for(@user, user_agent: "laptop", ip_address: "1.2.3.4")
    @device.remember_for(@user, user_agent: "stolen", ip_address: "1.2.3.4")

    (Studio::Auth::FAILURE_LIMIT / Studio::Auth::CODE_MAX_ATTEMPTS).times do
      issued = request_sign_in("cook@studio.com")
      Studio::Auth::CODE_MAX_ATTEMPTS.times { verify(issued, code: "000000x") }
    end

    issued = request_sign_in("cook@studio.com")
    assert LoginChallenge.find(issued.id).decoy?
    assert_equal :verified, verify(request_sign_in("cook@studio.com", device: owner_laptop)).status
  end

  test "real and unknown addresses run the same number of queries" do
    request_sign_in("warm@studio.com")
    real = count_queries { request_sign_in("cook@studio.com", device: stranger) }
    unknown = count_queries { request_sign_in("nobody@studio.com", device: stranger) }
    assert_equal real, unknown

    real_challenge = request_sign_in("cook@studio.com", device: stranger)
    decoy = request_sign_in("nobody@studio.com", device: stranger)
    assert_equal count_queries { verify(real_challenge, code: "000000x") }, count_queries { verify(decoy, code: "000000x") }
  end

  test "an account the app says cannot sign in gets decoys, and its codes stop working" do
    issued = request_sign_in("cook@studio.com")
    User.any_instance.stubs(:can_sign_in?).returns(false)

    assert_equal :invalid, verify(issued).status
    travel Studio::Auth::CODE_RESEND_INTERVAL + 1.second
    assert LoginChallenge.find(request_sign_in("cook@studio.com").id).decoy?
  end

  test "a review account locks after its daily cap of wrong codes, with an event and no mail" do
    with_review_accounts([{email_address: "review@studio.com", login_code: "381904"}]) do
      reviewer = User.create!(email_address: "review@studio.com")
      events = capture_event_names do
        perform_enqueued_jobs do
          (Studio::Auth::REVIEW_ACCOUNT_FAILURE_LIMIT / Studio::Auth::CODE_MAX_ATTEMPTS).times do
            issued = request_sign_in("review@studio.com", device: stranger)
            Studio::Auth::CODE_MAX_ATTEMPTS.times { verify(issued, code: "000000") }
          end
        end
      end

      assert Studio::Auth::Lockout.locked?(reviewer)
      assert_includes events, "authentication.review_account_locked"
      assert_empty ActionMailer::Base.deliveries
      assert LoginChallenge.find(request_sign_in("review@studio.com", device: stranger).id).decoy?
    end
  end

  test "the per-IP hourly limit is counted in the database" do
    Studio::Auth::SIGN_IN_IP_HOURLY_LIMIT.times { |n| request_sign_in("visitor#{n}@studio.com", device: stranger) }

    assert_equal :too_many_requests, request_sign_in("cook@studio.com")
  end

  test "IPv6 addresses in one /64 share a rate limit" do
    assert_equal Studio::Auth.rate_limit_key("2001:db8:1:2::1"), Studio::Auth.rate_limit_key("2001:db8:1:2:ffff::9")
    refute_equal Studio::Auth.rate_limit_key("2001:db8:1:2::1"), Studio::Auth.rate_limit_key("2001:db8:1:3::1")
    assert_equal "203.0.113.7", Studio::Auth.rate_limit_key("203.0.113.7")
  end

  test "signing in on a new device replaces its cookie, so a planted one never becomes known" do
    planted = @device.ensure_token!
    @user.update_columns(created_at: 1.day.ago)

    assert_equal :new, @device.remember_for(@user, user_agent: "test", ip_address: "1.2.3.4")
    refute_equal planted, @device.token
    assert @device.known_for?(@user)
  end

  test "after every known device is forgotten, the next sign-in is still a new device" do
    @user.update_columns(created_at: 1.day.ago)
    @device.remember_for(@user, user_agent: "test", ip_address: "1.2.3.4")
    @user.known_devices.delete_all

    assert_equal :new, stranger.remember_for(@user, user_agent: "attacker", ip_address: "6.6.6.6")
  end

  private

  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 if !payload[:name].to_s.include?("SCHEMA") && payload[:sql] !~ /\A(BEGIN|COMMIT|SAVEPOINT|RELEASE|ROLLBACK)/ }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  def request_sign_in(email_address, device: @device)
    Challenges.request_sign_in(email_address: email_address, device: device, ip_address: "1.2.3.4", user_agent: "test")
  end

  def stranger
    Studio::Auth::Device.new(ActionDispatch::TestRequest.create.cookie_jar)
  end

  def verify(issued, code: issued.code)
    Challenges.verify(id: issued.id, code: code, purpose: "sign_in")
  end

  def lock_account
    (Studio::Auth::FAILURE_LIMIT / Studio::Auth::CODE_MAX_ATTEMPTS).times do
      issued = Challenges.send(:issue, user: @user, purpose: "sign_in", known_device: false, device: stranger, ip_address: "6.6.6.6", user_agent: "attacker")
      Studio::Auth::CODE_MAX_ATTEMPTS.times { verify(issued, code: "000000x") }
      travel Studio::Auth::CODE_RESEND_INTERVAL + 1.second
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

  def with_review_accounts(entries)
    Rails.application.credentials.stubs(:dig).with(:studio_auth, :review_accounts).returns(entries)
    Studio::Auth::ReviewAccounts.reset!
    yield
  end
end
