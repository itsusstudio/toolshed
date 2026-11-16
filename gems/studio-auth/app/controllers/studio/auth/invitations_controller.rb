module Studio
  module Auth
    class InvitationsController < BaseController
      allow_unauthenticated_access
      before_action :set_invitation

      rate_limit to: 20, within: 1.minute, name: "ip", by: -> { rate_limit_key }, with: :invitation_unavailable

      def show
      end

      def update
        user = @invitation.user
        @invitation.accept!
        start_new_session_for(user)
        Rails.event.notify("authentication.invitation_accepted", actor_id: user.id)
        after_invitation_accepted(user)
        redirect_to after_authentication_path, status: :see_other
      rescue ActiveRecord::RecordInvalid
        invitation_unavailable
      end

      private

      def set_invitation
        @invitation = Invitation.find_pending_by_token(params[:token])
        invitation_unavailable if @invitation.nil? || !@invitation.user.can_be_invited?
      end

      def invitation_unavailable
        redirect_to main_app.login_path, status: :see_other, alert: t("studio_auth.flash.invitation_unavailable")
      end
    end
  end
end
