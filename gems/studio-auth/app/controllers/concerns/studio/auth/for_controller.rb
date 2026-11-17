module Studio
  module Auth
    module ForController
      extend ActiveSupport::Concern

      RETURN_TO_KEY = :studio_auth_return_to
      VERIFIED_EMAIL_KEY = :studio_auth_verified_email_address
      VERIFIED_EMAIL_TTL = 30.minutes
      NEW_ACCOUNT_EMAIL_KEY = :studio_auth_new_account_email_address

      include Authentication
      include Sessions
      include ReturnPath
      include Codes
      include SignUp
    end
  end
end
