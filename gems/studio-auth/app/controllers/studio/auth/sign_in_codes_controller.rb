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
        result = VerifyCode.call(id: @pending.id, code: submitted_code)

        status, user = result.status, result.user
        if status == :verified && user.nil?
          clear_pending_login_code
          return continue_sign_up(result.email_address)
        end

        case status
        when :verified
          clear_pending_login_code
          start_new_session_for(user)
          redirect_to after_authentication_path, status: :see_other
        when :invalid
          @field_error = t("studio_auth.errors.code.invalid")
          render :new, status: :unprocessable_content
        else
          flash[:alert] = t("studio_auth.flash.#{status}")
          flash[:studio_auth_email_address] = @pending.email_address
          clear_pending_login_code
          redirect_to main_app.login_path, status: :see_other
        end
      end
    end
  end
end
