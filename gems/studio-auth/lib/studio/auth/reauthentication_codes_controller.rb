module Studio
  module Auth
    class ReauthenticationCodesController < BaseController
      before_action { require_pending_challenge("reauthentication") }

      rate_limit to: 20, within: 1.minute, only: :create, name: "ip", by: -> { Auth.rate_limit_key(request.remote_ip) }, with: :too_many_requests

      def new
      end

      def create
        result = Challenges.verify(id: @pending["id"], code: submitted_code, purpose: "reauthentication", user: current_user)

        case result.status
        when :verified
          clear_pending_challenge
          current_session.reauthenticated!
          Events.notify("reauthenticated", actor_id: current_user.id)
          redirect_to after_authentication_path, status: :see_other
        when :invalid
          flash.now[:alert] = t("studio_auth.flash.wrong_code")
          render_new(:unprocessable_content)
        else
          clear_pending_challenge
          redirect_to main_app.reauthentication_path, status: :see_other, alert: t("studio_auth.flash.#{result.status}")
        end
      end
    end
  end
end
