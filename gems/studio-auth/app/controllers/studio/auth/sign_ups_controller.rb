module Studio
  module Auth
    class SignUpsController < BaseController
      allow_unauthenticated_access
      before_action -> { device_cookie.ensure_device_token! }, only: :new
      before_action :redirect_signed_in, only: :new

      rate_limit to: 10, within: 1.minute, only: :create, name: "ip",
        by: -> { rate_limit_key }, with: :too_many_requests
      rate_limit to: SignInLimits::IP_HOURLY_LIMIT, within: 1.hour, only: :create, name: "ip_hourly",
        by: -> { rate_limit_key }, with: :too_many_requests

      def new
        @no_account_email_address = flash[:studio_auth_no_account]
        @form = SignUpForm.new(email_address: @no_account_email_address)
      end

      def create
        @form = build_form
        return render(:new, status: :unprocessable_content) if @form.invalid?

        issued = RequestCode.call(email_address: @form.email_address, **code_request_details)
        if issued.is_a?(Symbol)
          @form.errors.add(:email_address, issued)
          return render(:new, status: (issued == :undeliverable) ? :unprocessable_content : :too_many_requests)
        end

        email_address = TypedInput.email_address(@form.email_address)
        session[SIGN_UP_DETAILS_KEY] = {
          "email_address" => email_address, "full_name" => @form.full_name, "time_zone" => @form.time_zone.presence
        }
        Rails.event.notify("authentication.sign_up_started")
        PendingLoginCode.store_in_rails_session(session, issued, email_address: email_address)
        redirect_to main_app.verify_path, status: :see_other
      end

      private

      def build_form
        SignUpForm.new(full_name: params[:full_name], email_address: params[:email_address], time_zone: params[:time_zone])
      end
    end
  end
end
