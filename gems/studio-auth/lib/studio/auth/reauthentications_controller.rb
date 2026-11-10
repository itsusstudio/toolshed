module Studio
  module Auth
    class ReauthenticationsController < BaseController
      rate_limit to: 5, within: 1.hour, only: :create, name: "user", by: -> { current_user.id }, with: :too_many_requests

      def new
      end

      def create
        issued = Challenges.request_reauthentication(
          user: current_user, device: device, ip_address: request.remote_ip, user_agent: request.user_agent
        )
        start_pending_challenge(issued, purpose: "reauthentication", email_address: current_user.email_address)
        redirect_to main_app.reauthentication_verify_path, status: :see_other
      end
    end
  end
end
