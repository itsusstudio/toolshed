module Studio
  module Auth
    module ForController
      # Turns a verified sign-up into a user. Apps with setup take the pending
      # sign-up into their own screen and call finish_sign_up there; apps
      # without get the user created here, through prepare_new_user.
      module SignUp
        extend ActiveSupport::Concern

        included do
          helper_method :pending_sign_up
        end

        private

        # The app's setup screen, for apps that need a tenant or settings
        # before the user exists. Nil creates the user straight after the code.
        def sign_up_setup_path
        end

        # Sets the app's own defaults on a new user before its first save,
        # for apps without setup. pending_sign_up is available here.
        def prepare_new_user(user)
        end

        def after_sign_up(user)
          after_authentication_path
        end

        def pending_sign_up
          @pending_sign_up ||= PendingSignUp.from_cookie(cookies)
        end

        # Called by the app's setup once it has created the user, inside or
        # after the transaction that created it.
        def finish_sign_up(user)
          PendingSignUp.where(email_address: user.email_address).delete_all
          PendingSignUp.delete_cookie(cookies)
          @pending_sign_up = nil
          start_new_session_for(user)
          Rails.event.notify("authentication.sign_up_completed", actor_id: user.id)
        end

        def continue_sign_up(email_address)
          pending = record_pending_sign_up(email_address)
          return redirect_to(main_app.signup_path, status: :see_other) if pending.nil?

          pending.write_cookie(cookies)
          @pending_sign_up = pending
          if (setup_path = sign_up_setup_path)
            return redirect_to(setup_path, status: :see_other)
          end

          user = ::User.new(email_address: pending.email_address, full_name: pending.full_name)
          prepare_new_user(user)
          user.save!
          finish_sign_up(user)
          redirect_to after_sign_up(user), status: :see_other
        end

        # The details typed on the signup form ride in the session until the
        # code checks out. Without them, as when someone comes back through
        # the sign-in page, an earlier pending sign-up carries on.
        def record_pending_sign_up(email_address)
          details = session.delete(SIGN_UP_DETAILS_KEY)
          if details.is_a?(Hash) && details["email_address"] == email_address
            PendingSignUp.record!(email_address: email_address, full_name: details["full_name"],
              time_zone: details["time_zone"])
          else
            PendingSignUp.live.find_by(email_address: email_address)
          end
        end

        # The address typed on the sign-in page within the last
        # NEW_ACCOUNT_EMAIL_TTL that had no account, or nil. Unverified: the
        # signup form only prefills its email field from it.
        def new_account_email_address
          typed = session[NEW_ACCOUNT_EMAIL_KEY]
          return if !typed.is_a?(Hash) || typed["typed_at"].to_i <= NEW_ACCOUNT_EMAIL_TTL.ago.to_i

          typed["email_address"]
        end
      end
    end
  end
end
