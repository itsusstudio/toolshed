module Studio
  module Auth
    module ForController
      module SignUp
        extend ActiveSupport::Concern

        included do
          helper_method :pending_sign_up
        end

        private

        def finish_sign_up_path
          path = Auth.config.finish_sign_up_path
          main_app.public_send(path) if path
        end

        def prepare_new_user(user)
        end

        def after_sign_up(user)
          after_authentication_path
        end

        def pending_sign_up
          @pending_sign_up ||= PendingSignUp.from_cookie(cookies)
        end

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
          if (finish_path = finish_sign_up_path)
            return redirect_to(finish_path, status: :see_other)
          end

          user = ::User.new(email_address: pending.email_address, full_name: pending.full_name)
          prepare_new_user(user)
          user.save!
          finish_sign_up(user)
          redirect_to after_sign_up(user), status: :see_other
        end

        def record_pending_sign_up(email_address)
          details = session.delete(SIGN_UP_DETAILS_KEY)
          if details.is_a?(Hash) && details["email_address"] == email_address
            PendingSignUp.record!(email_address: email_address, full_name: details["full_name"],
              time_zone: details["time_zone"])
          else
            PendingSignUp.live.find_by(email_address: email_address)
          end
        end
      end
    end
  end
end
