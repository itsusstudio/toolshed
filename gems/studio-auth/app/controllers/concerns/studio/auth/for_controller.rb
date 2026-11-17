module Studio
  module Auth
    module ForController
      extend ActiveSupport::Concern

      RETURN_TO_KEY = :studio_auth_return_to
      NEW_ACCOUNT_EMAIL_KEY = :studio_auth_new_account_email_address
      NEW_ACCOUNT_EMAIL_TTL = 30.minutes
      SIGN_UP_DETAILS_KEY = :studio_auth_sign_up_details

      include Authentication
      include Sessions
      include ReturnPath
      include Codes
      include SignUp
    end
  end
end
