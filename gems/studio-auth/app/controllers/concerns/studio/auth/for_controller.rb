module Studio
  module Auth
    module ForController
      extend ActiveSupport::Concern

      RETURN_TO_KEY = :studio_auth_return_to
      SIGN_UP_DETAILS_KEY = :studio_auth_sign_up_details

      include Authentication
      include Sessions
      include ReturnPath
      include Codes
      include SignUp
      include Reauthentication
    end
  end
end
