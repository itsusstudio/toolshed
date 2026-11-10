module Studio
  module Auth
    class BaseController < ::ApplicationController
      private

      def too_many_requests
        flash.now[:alert] = t("studio_auth.flash.too_many_requests")
        render_new(:too_many_requests)
      end

      def render_new(status)
        render :new, status: status
      end

      def require_pending_challenge(purpose)
        @pending = pending_challenge
        return if @pending && @pending["purpose"] == purpose

        clear_pending_challenge
        redirect_to((purpose == "sign_in") ? main_app.login_path : main_app.reauthentication_path, status: :see_other)
      end

      def submitted_code
        Auth.ascii_digits(params[:code]).gsub(/\D/, "")
      end

      def device
        Device.new(cookies)
      end
    end
  end
end
