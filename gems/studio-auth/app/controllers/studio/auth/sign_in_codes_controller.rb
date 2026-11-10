module Studio
  module Auth
    class SignInCodesController < BaseController
      allow_unauthenticated_access
      before_action :require_pending_login_code

      rate_limit to: 20, within: 1.minute, only: :create, name: "ip",
        by: -> { rate_limit_key }, with: :too_many_requests

      def new
      end

      def create
        result = LoginCode.verify(id: @pending.id, code: submitted_code)

        case result.status
        when :verified
          clear_pending_login_code
          start_new_session_for(result.user)
          redirect_to after_authentication_path, status: :see_other
        when :invalid
          flash.now[:alert] = t("studio_auth.flash.wrong_code")
          render :new, status: :unprocessable_content
        else
          clear_pending_login_code
          redirect_to main_app.login_path, status: :see_other, alert: t("studio_auth.flash.#{result.status}")
        end
      end
    end
  end
end
