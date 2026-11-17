module Studio
  module Auth
    class SignUpsController < BaseController
      FULL_NAME_MAX_LENGTH = 100

      allow_unauthenticated_access
      before_action :require_sign_up
      before_action -> { device_cookie.ensure_device_token! }, only: :new
      before_action :redirect_signed_in, only: :new

      rate_limit to: 10, within: 1.minute, only: :create, name: "ip",
        by: -> { rate_limit_key }, with: :too_many_requests
      rate_limit to: SignInLimits::IP_HOURLY_LIMIT, within: 1.hour, only: :create, name: "ip_hourly",
        by: -> { rate_limit_key }, with: :too_many_requests

      def new
        @email_address = new_account_email_address
      end

      def create
        @full_name = params[:full_name].to_s.squish
        @email_address = params[:email_address]
        @full_name_error = full_name_error
        return render(:new, status: :unprocessable_content) if @full_name_error

        issued = RequestCode.call(email_address: @email_address, **code_request_details)
        if issued == :undeliverable
          @field_error = t("studio_auth.flash.undeliverable")
          return render(:new, status: :unprocessable_content)
        end
        return too_many_requests if issued == :too_many_requests

        email_address = TypedInput.email_address(@email_address)
        session[SIGN_UP_DETAILS_KEY] = {
          "email_address" => email_address, "full_name" => @full_name, "time_zone" => params[:time_zone].presence
        }
        Rails.event.notify("authentication.sign_up_started")
        PendingLoginCode.store_in_rails_session(session, issued, email_address: email_address)
        redirect_to main_app.verify_path, status: :see_other
      end

      private

      def full_name_error
        if @full_name.blank?
          t("studio_auth.flash.full_name_missing")
        elsif @full_name.length > FULL_NAME_MAX_LENGTH
          t("studio_auth.flash.full_name_too_long", count: FULL_NAME_MAX_LENGTH)
        end
      end

      def require_sign_up
        redirect_to main_app.login_path, status: :see_other if !Studio::Auth.sign_up?
      end
    end
  end
end
