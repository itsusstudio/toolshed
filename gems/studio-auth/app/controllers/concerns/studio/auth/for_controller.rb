module Studio
  module Auth
    module ForController
      extend ActiveSupport::Concern

      RETURN_TO_KEY = :studio_auth_return_to

      included do
        before_action :require_authentication
        helper_method :authenticated?, :current_user
      end

      class_methods do
        def allow_unauthenticated_access(**options)
          skip_before_action :require_authentication, **options
        end
      end

      private

      def authenticated?
        current_session.present?
      end

      # ||= alone would query again on every call when the cookie names no
      # live session.
      def current_session
        return ::Current.session if ::Current.session || @studio_session_resumed

        @studio_session_resumed = true
        assign_current_session(::Session.from_cookie(cookies))
      end

      def current_user
        current_session&.user
      end

      def require_authentication
        current_session || request_authentication
      end

      def request_authentication
        # On a 401 the Hotwire Native shells swap their tabs for a sign-in
        # screen. A redirect would load /login inside the tab that asked.
        return head(:unauthorized) if native_app_request?

        store_return_path(request.fullpath) if request.get? || request.head?

        redirect_to main_app.login_path
      end

      def after_authentication_path
        session.delete(RETURN_TO_KEY) || main_app.root_path
      end

      def start_sign_in_for(user)
        issued = LoginCode.request_for(
          email_address: user.email_address, device_cookie: DeviceCookie.new(cookies),
          ip_address: request.remote_ip, user_agent: request.user_agent
        )
        if issued == :undeliverable || issued == :too_many_requests
          return redirect_to(main_app.login_path, status: :see_other, alert: t("studio_auth.flash.#{issued}"))
        end

        PendingLoginCode.store_in_rails_session(session, issued, email_address: user.email_address)
        redirect_to main_app.verify_path, status: :see_other
      end

      # reset_session drops any session id an attacker planted before sign-in.
      # The browser's previous session row ends too, so a copy of its old
      # cookie stops working.
      def start_new_session_for(user)
        current_session&.destroy
        return_to = session[RETURN_TO_KEY]
        reset_session
        session[RETURN_TO_KEY] = return_to if return_to

        new_session = user.sessions.create!(**request_details)
        new_session.write_cookie(cookies)
        assign_current_session(new_session)
        Rails.event.notify("authentication.session_started", actor_id: user.id)

        DeviceCookie.new(cookies).trust_for(user, **request_details)
        after_sign_in(user)
        new_session
      end

      def after_sign_in(user)
      end

      def terminate_session
        if (session = current_session)
          Rails.event.notify("authentication.session_ended") if session.destroy
          disconnect_cable([session])
        end
        forget_session
      end

      def terminate_all_sessions
        if (user = current_user)
          sessions = user.sessions.to_a
          user.sessions.delete_all
          disconnect_cable(sessions)
          user.known_devices.delete_all
          user.login_codes.live.update_all(expires_at: Time.current)
          Rails.event.notify("authentication.all_sessions_ended", actor_id: user.id)
        end
        forget_session
      end

      # An open socket outlives its cookie and would keep receiving
      # broadcasts. ForCableConnection identifies sockets by session.
      def disconnect_cable(sessions)
        return if !defined?(::ActionCable)

        sessions.each { ::ActionCable.server.remote_connections.where(current_session: it).disconnect }
      end

      def forget_session
        assign_current_session(nil)
        ::Session.delete_cookie(cookies)
        reset_session
      end

      def native_app_request?
        respond_to?(:hotwire_native_app?, true) && hotwire_native_app?
      end

      def request_details
        {user_agent: request.user_agent, ip_address: request.remote_ip}
      end

      def assign_current_session(new_session)
        ::Current.session = new_session
        Studio::Monitoring::Current.actor_id = new_session&.user_id if defined?(Studio::Monitoring::Current)
        new_session
      end

      def store_return_path(path)
        if safe_return_path?(path)
          session[RETURN_TO_KEY] = path
        else
          session.delete(RETURN_TO_KEY)
        end
      end

      def safe_return_path?(path)
        path.is_a?(String) && path.start_with?("/") && !path.start_with?("//")
      end
    end
  end
end
