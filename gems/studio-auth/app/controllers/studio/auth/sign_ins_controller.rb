module Studio
  module Auth
    class SignInsController < BaseController
      allow_unauthenticated_access only: [:new, :create]
      before_action -> { device_cookie.ensure_device_token! }, only: :new
      before_action :redirect_signed_in, only: :new

      rate_limit to: 10, within: 1.minute, only: :create, name: "ip",
        by: -> { rate_limit_key }, with: :too_many_requests
      rate_limit to: SignInLimits::IP_HOURLY_LIMIT, within: 1.hour, only: :create, name: "ip_hourly",
        by: -> { rate_limit_key }, with: :too_many_requests

      def new
        @email_address = flash[:studio_auth_email_address] ||
          PendingLoginCode.from_rails_session(session)&.email_address
      end

      def create
        @email_address = params[:email_address]
        resend = params[:resend].present? && pending_code_email_address?
        issued = RequestCode.call(
          email_address: @email_address, device_cookie: device_cookie,
          ip_address: request.remote_ip, user_agent: request.user_agent,
          account_required: !resend, resend: resend
        )

        if issued == :no_account
          flash[:studio_auth_no_account] = TypedInput.email_address(@email_address)
          return redirect_to(main_app.signup_path, status: :see_other)
        end
        if issued.is_a?(Symbol)
          @field_error = t("studio_auth.errors.email_address.#{issued}")
          return render(:new, status: (issued == :undeliverable) ? :unprocessable_content : :too_many_requests)
        end

        email_address = TypedInput.email_address(@email_address)
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

      def pending_code_email_address?
        pending = PendingLoginCode.from_rails_session(session)
        pending.present? && pending.email_address == TypedInput.email_address(params[:email_address])
      end
    end
  end
end
