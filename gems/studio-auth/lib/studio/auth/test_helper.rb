module Studio
  module Auth
    # For integration tests: signs in without the email code, so tests that
    # aren't about sign-in skip the mail round trip.
    module TestHelper
      def sign_in_as(user)
        session = user.sessions.create!(user_agent: "Rails Testing", ip_address: "127.0.0.1")
        @studio_auth_test_session = session
        ::Current.session = session
        ActionDispatch::TestRequest.create.cookie_jar.tap do |jar|
          session.write_cookie(jar)
          jar.each { |name, value| cookies[name] = value }
        end
        session
      end

      def sign_out
        @studio_auth_test_session&.destroy!
        cookies.delete(ForSession::COOKIE_NAME.to_s)
        ::Current.session = nil
      end

      def assert_requires_authentication
        reset!
        yield
        assert_redirected_to login_path
      end

      def assert_allows_unauthenticated_access
        reset!
        yield
        assert_response :success
      end
    end
  end
end
