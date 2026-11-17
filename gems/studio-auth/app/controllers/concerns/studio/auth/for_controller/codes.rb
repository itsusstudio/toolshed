module Studio
  module Auth
    module ForController
      # Asking for a code and showing the code page.
      module Codes
        extend ActiveSupport::Concern

        private

        def start_sign_in_for(user)
          issued = RequestCode.call(email_address: user.email_address, **code_request_details)
          redirect_to_code_page(issued, TypedInput.email_address(user.email_address))
        end

        def code_request_details
          {device_cookie: DeviceCookie.new(cookies), ip_address: request.remote_ip, user_agent: request.user_agent}
        end

        def redirect_to_code_page(issued, email_address)
          if issued == :undeliverable || issued == :too_many_requests
            return redirect_to(main_app.login_path, status: :see_other, alert: t("studio_auth.flash.#{issued}"))
          end

          PendingLoginCode.store_in_rails_session(session, issued, email_address: email_address)
          redirect_to main_app.verify_path, status: :see_other
        end
      end
    end
  end
end
