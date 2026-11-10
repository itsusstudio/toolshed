module Studio
  module Auth
    class SignInsController < BaseController
      allow_unauthenticated_access only: [:new, :create]
      before_action :redirect_signed_in, only: :new
      before_action -> { device.ensure_token! }, only: :new

      rate_limit to: 10, within: 1.minute, only: :create, name: "ip", by: -> { Auth.rate_limit_key(request.remote_ip) }, with: :too_many_requests
      rate_limit to: SIGN_IN_IP_HOURLY_LIMIT, within: 1.hour, only: :create, name: "ip_hourly", by: -> { Auth.rate_limit_key(request.remote_ip) }, with: :too_many_requests

      def new
      end

      def create
        issued = Challenges.request_sign_in(
          email_address: params[:email_address], device: device,
          ip_address: request.remote_ip, user_agent: request.user_agent
        )

        if issued == :undeliverable
          @email_address_error = t("studio_auth.flash.undeliverable")
          return render_new(:unprocessable_content)
        end
        return too_many_requests if issued == :too_many_requests

        start_pending_challenge(issued, purpose: "sign_in", email_address: Auth.normalize_email(params[:email_address]))
        redirect_to main_app.verify_path, status: :see_other
      end

      def destroy
        terminate_session
        redirect_to main_app.login_path, status: :see_other, notice: t("studio_auth.flash.signed_out")
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
