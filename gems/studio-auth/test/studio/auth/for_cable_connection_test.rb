require "test_helper"

class Studio::Auth::ForCableConnectionTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection

  test "#connect rejects a socket without a live session" do
    assert_reject_connection { connect }

    cookies.signed[:session_id] = "nonexistent"
    assert_reject_connection { connect }
  end

  test "#connect identifies the socket by the cookie's session" do
    user = User.create!(email_address: "cook@studio.com")
    session = user.sessions.create!
    cookies.signed[:session_id] = session.id

    connect

    assert_equal session, connection.current_session
    assert_equal user, connection.current_user
  end
end
