require "ipaddr"

module Studio
  module Auth
    class BaseController < ::ApplicationController
      private

      def too_many_requests
        flash.now[:alert] = t("studio_auth.flash.too_many_requests")
        render :new, status: :too_many_requests
      end

      def require_pending_login_code
        @pending = PendingLoginCode.from_rails_session(session)
        redirect_to main_app.login_path, status: :see_other if @pending.nil?
      end

      def clear_pending_login_code
        PendingLoginCode.delete_from_rails_session(session)
      end

      def submitted_code
        TypedInput.code(params[:code])
      end

      def device_cookie
        DeviceCookie.new(cookies)
      end

      # One IPv6 customer usually holds a whole /64, so per-IP limits count
      # the /64; otherwise each of its addresses would get a fresh limit.
      def rate_limit_key
        address = IPAddr.new(request.remote_ip.to_s)
        (address.ipv6? && !address.ipv4_mapped?) ? address.mask(64).to_s : address.to_s
      rescue IPAddr::InvalidAddressError
        request.remote_ip.to_s
      end
    end
  end
end
