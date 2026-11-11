module Studio
  module Auth
    class SignInsController < BaseController
      allow_unauthenticated_access only: [:new, :create]
      # Set before the code request, so a retry after a lost response still
      # carries the device token and gets the same code back.
      before_action -> { device_cookie.ensure_device_token! }, only: :new
      before_action :redirect_signed_in, only: :new

      rate_limit to: 10, within: 1.minute, only: :create, name: "ip",
        by: -> { rate_limit_key }, with: :too_many_requests
      rate_limit to: LoginCode::IP_HOURLY_LIMIT, within: 1.hour, only: :create, name: "ip_hourly",
        by: -> { rate_limit_key }, with: :too_many_requests

      def new
      end

      def create
        issued = LoginCode.request_for(
          email_address: params[:email_address], device_cookie: device_cookie,
          ip_address: request.remote_ip, user_agent: request.user_agent
        )

        if issued == :undeliverable
          @email_address_error = t("studio_auth.flash.undeliverable")
          return render(:new, status: :unprocessable_content)
        end
        return too_many_requests if issued == :too_many_requests

        email_address = TypedInput.email_address(params[:email_address])
        PendingLoginCode.store_in_rails_session(session, issued, email_address: email_address)
        redirect_to main_app.verify_path, status: :see_other
      end

      def destroy
        terminate_session
        redirect_to main_app.login_path, status: :see_other
      end

      def destroy_all
        terminate_all_sessions
        redirect_to main_app.login_path, status: :see_other, notice: t("studio_auth.flash.signed_out_everywhere")
      end

      private

      def redirect_signed_in
        redirect_to main_app.root_path if authenticated?
      end
    end
  end
end
