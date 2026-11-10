module Studio
  module Auth
    module ForStaffController
      extend ActiveSupport::Concern

      included do
        before_action :require_staff
        after_action :record_admin_action, if: :admin_write?
      end

      private

      # A 404, not a 403 or a redirect, so the admin area doesn't confirm it
      # exists to anyone else.
      def require_staff
        if !current_user.staff?
          Rails.event.notify("authentication.admin_access_denied", actor_id: current_user.id, path: request.path)
          raise ActionController::RoutingError, "Not Found"
        end

        if !current_session.recent_enough_for_staff?(write: admin_write?)
          return_to = admin_return_path
          terminate_session
          store_return_path(return_to) if return_to
          return redirect_to(main_app.login_path, notice: t("studio_auth.flash.admin_sign_in_again"))
        end

        response.set_header("X-Robots-Tag", "noindex, nofollow")
      end

      # A form post can't be replayed after sign-in, so a write returns to
      # the page the form was on, to submit again.
      def admin_return_path
        return request.fullpath if !admin_write?

        URI.parse(request.referer.to_s).path.presence
      rescue URI::InvalidURIError
        nil
      end

      def admin_write?
        !request.get? && !request.head?
      end

      def record_admin_action
        Rails.event.notify("authentication.admin_action", actor_id: current_user.id, method: request.method,
          path: request.path, controller: controller_path, action: action_name, status: response.status)
      end
    end
  end
end
