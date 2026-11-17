module Studio
  module Auth
    module ForController
      # Hands a verified address with no account to the app's signup form.
      module SignUp
        extend ActiveSupport::Concern

        private

        # Apps with sign-up return the new user for a verified address, nil to
        # send the visitor back to sign in, or redirect (to finish a signup form).
        # By default an app with a signup route gets the visitor there with the
        # address verified, so the form needs no second code. The address rides
        # in the session, never the URL: analytics and history record URLs.
        def create_account_for(email_address)
          return if !Studio::Auth.sign_up?

          session[VERIFIED_EMAIL_KEY] = {"email_address" => email_address, "verified_at" => Time.current.to_i}
          redirect_to main_app.signup_path, status: :see_other
        end

        # The address this browser proved it reads within the last
        # VERIFIED_EMAIL_TTL, or nil. A signup form fills its email field from it.
        def verified_email_address
          verified = session[VERIFIED_EMAIL_KEY]
          return if !verified.is_a?(Hash) || verified["verified_at"].to_i <= VERIFIED_EMAIL_TTL.ago.to_i

          verified["email_address"]
        end

        # The address typed on the sign-in page within the last
        # VERIFIED_EMAIL_TTL that had no account, or nil. Unverified: a signup
        # form may only prefill its email field from it.
        def new_account_email_address
          typed = session[NEW_ACCOUNT_EMAIL_KEY]
          return if !typed.is_a?(Hash) || typed["typed_at"].to_i <= VERIFIED_EMAIL_TTL.ago.to_i

          typed["email_address"]
        end

        # Whether +email_address+ is that verified address. A signup form checks
        # it to create the account and sign in without mailing a second code.
        def verified_email_address?(email_address)
          verified_email_address.present? && verified_email_address == TypedInput.email_address(email_address)
        end
      end
    end
  end
end
