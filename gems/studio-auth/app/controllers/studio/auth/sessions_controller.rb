module Studio
  module Auth
    class SessionsController < BaseController
      # The current session leaves through logout_path, so its id here is
      # treated like one that is already gone.
      def destroy
        other_sessions = current_user.sessions.where.not(id: current_session.id)
        if other_sessions.exists?(id: params[:id])
          end_sessions(other_sessions.where(id: params[:id]))
          Rails.event.notify("authentication.session_ended", actor_id: current_user.id)
        end

        redirect_back_or_to main_app.root_path, status: :see_other, notice: t("studio_auth.flash.signed_out_device")
      end
    end
  end
end
