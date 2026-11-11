require "test_helper"

class Studio::Auth::SessionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include AuthenticationTestHelpers

  test "#destroy requires authentication" do
    other = create_authentication_user("cook@studio.com").sessions.create!

    delete logout_session_path(other)

    assert_redirected_to login_path
    assert Session.exists?(other.id)
  end

  test "#destroy ends that session and its sockets and leaves the rest signed in" do
    sign_in_with_code("cook@studio.com")
    current = Session.last
    other, untouched = 2.times.map { User.first.sessions.create! }

    delete logout_session_path(other)

    assert_redirected_to root_path
    assert_equal [current.id, untouched.id].sort, Session.pluck(:id).sort
    assert_equal 1, cable_disconnects(other)
    get "/private"
    assert_response :success
  end

  test "#destroy leaves the current session alone" do
    sign_in_with_code("cook@studio.com")
    current = Session.last

    delete logout_session_path(current)

    assert Session.exists?(current.id)
  end

  test "#destroy is a no-op for a session that is already gone" do
    sign_in_with_code("cook@studio.com")

    delete logout_session_path(id: 0)

    assert_redirected_to root_path
    assert_equal 1, Session.count
  end

  private

  def cable_disconnects(session)
    ActionCable.server.pubsub.broadcasts("action_cable/#{session.to_gid_param}").size
  end

  def request_authentication_code(email_address)
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { post login_path, params: {email_address: email_address} }
    ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
  end
end
