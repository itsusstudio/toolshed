module Studio
  module Admin
    # For integration tests of an app's admin pages. Uses the app's
    # sign_in_as, so include it next to Studio::Auth::TestHelper or the app's
    # own session helpers.
    module TestHelper
      # Signed-out visitors go to sign in; a signed-in user who isn't staff
      # goes to the app's root.
      def assert_requires_staff(non_staff_user)
        reset!
        yield
        assert_redirected_to login_path

        sign_in_as(non_staff_user)
        yield
        assert_redirected_to root_path
      end
    end
  end
end
