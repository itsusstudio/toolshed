require "ipaddr"

module Studio
  module Auth
    class BaseController < ::ApplicationController
      layout "studio/auth"
      helper FormsHelper

      private

      def too_many_requests
        @form ||= build_form if respond_to?(:build_form, true)
        @email_address ||= params[:email_address]
        @field_error = t("studio_auth.flash.too_many_requests")
        render :new, status: :too_many_requests
      end

      def submitted_code
        TypedInput.code(params[:code])
      end

      def require_pending_login_code
        @pending = PendingLoginCode.from_rails_session(session)
        redirect_to main_app.login_path, status: :see_other if @pending.nil?
      end

      def clear_pending_login_code
        PendingLoginCode.delete_from_rails_session(session)
      end

      def redirect_signed_in
        redirect_to main_app.root_path if authenticated? && !reauthentication_requested?
      end

      def device_cookie
        DeviceCookie.new(cookies)
      end

      def rate_limit_key
        address = IPAddr.new(request.remote_ip.to_s)
        (address.ipv6? && !address.ipv4_mapped?) ? address.mask(64).to_s : address.to_s
      rescue IPAddr::InvalidAddressError
        request.remote_ip.to_s
      end
    end
  end
end
