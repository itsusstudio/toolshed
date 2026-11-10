require "test_helper"

class Studio::Auth::ForSessionTest < ActiveSupport::TestCase
  IDLE = Studio::Auth.config.session_idle_timeout
  ABSOLUTE = Studio::Auth.config.session_absolute_timeout

  setup do
    @user = User.create!(email_address: "cook@studio.com")
    @session = @user.sessions.create!
    @jar = ActionDispatch::TestRequest.create.cookie_jar
    @session.remember_in(@jar)
  end

  test "a session idle past the idle timeout is refused" do
    travel IDLE + 1.minute
    assert_nil Session.from_cookie(@jar)
  end

  test "regular use keeps a session up to the absolute timeout" do
    step = IDLE - 1.day
    travel(step) { assert Session.from_cookie(@jar) }
    travel(step * 2) { assert Session.from_cookie(@jar) }
    travel(ABSOLUTE + 1.minute) { assert_nil Session.from_cookie(@jar) }
  end

  test "a session from before the gem, with no last_seen_at, stays active and gets one" do
    @session.update_columns(last_seen_at: nil, created_at: 60.days.ago)

    assert_equal @session, Session.from_cookie(@jar)
    assert_not_nil @session.reload.last_seen_at
  end

  test "last_seen_at is touched at most once per throttle window" do
    seen = @session.last_seen_at

    travel(10.minutes) { Session.from_cookie(@jar) }
    assert_equal seen, @session.reload.last_seen_at

    travel(Studio::Auth::SESSION_TOUCH_THROTTLE + 1.minute) { Session.from_cookie(@jar) }
    assert_operator @session.reload.last_seen_at, :>, seen
  end

  test "the cookie expires with the absolute timeout" do
    cookie = @jar.instance_variable_get(:@set_cookies)["session_id"]

    assert_equal @session.cookie_expires_at.to_i, cookie[:expires].to_i
    assert cookie[:httponly]
  end

  test "PurgeExpiredJob deletes expired sessions and codes past the failure window" do
    Studio::Auth::LoginCode.create!(code_digest: "d", expires_at: 1.minute.from_now)

    travel IDLE + 1.minute do
      fresh = @user.sessions.create!
      Studio::Auth::PurgeExpiredJob.perform_now

      assert_equal [fresh], Session.all.to_a
      assert_equal 0, Studio::Auth::LoginCode.count
    end
  end
end
