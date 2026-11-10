module Studio
  module Auth
    module Controller
      extend ActiveSupport::Concern

      RETURN_TO_KEY = :studio_auth_return_to
      PENDING_KEY = :studio_auth_pending

      included do
        before_action :require_authentication
        helper_method :authenticated?, :current_user, :recently_authenticated?
      end

      class_methods do
        def allow_unauthenticated_access(**options)
          skip_before_action :require_authentication, **options
        end

        def require_recent_authentication(within: REAUTHENTICATION_WINDOW, **options)
          before_action(**options) { recently_authenticated?(within: within) || request_reauthentication }
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
        resumed = ::Session.from_cookie(cookies)
        assign_current_session((resumed if resumed&.user&.can_sign_in?))
      end

      def current_user
        current_session&.user
      end

      def recently_authenticated?(within: REAUTHENTICATION_WINDOW)
        !!current_session&.recently_authenticated?(within: within)
      end

      def require_authentication
        current_session || request_authentication
      end

      def request_authentication
        remember_return_to(request.fullpath) if request.get? || request.head?
        return head(:unauthorized) if native_app_request?

        redirect_to main_app.login_path
      end

      def request_reauthentication
        remember_return_to((request.get? || request.head?) ? request.fullpath : same_origin_referrer_path)
        redirect_to main_app.reauthentication_path
      end

      def after_authentication_path
        session.delete(RETURN_TO_KEY) || main_app.root_path
      end

      def start_sign_in_for(user)
        issued = Challenges.request_sign_in(
          email_address: user.email_address, device: Device.new(cookies),
          ip_address: request.remote_ip, user_agent: request.user_agent
        )
        if issued == :undeliverable || issued == :too_many_requests
          return redirect_to(main_app.login_path, status: :see_other, alert: t("studio_auth.flash.#{issued}"))
        end

        start_pending_challenge(issued, purpose: "sign_in", email_address: user.email_address)
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

        new_session = user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip)
        new_session.remember_in(cookies)
        assign_current_session(new_session)
        Events.notify("session_started", actor_id: user.id)

        device = Device.new(cookies).remember_for(user, user_agent: request.user_agent, ip_address: request.remote_ip)
        if device == :new
          Mailer.with(user: user, user_agent: request.user_agent, ip_address: request.remote_ip, signed_in_at: Time.current).new_device.deliver_later
        end
        after_sign_in(user)
        new_session
      end

      # Apps override this to act on a fresh sign-in, e.g. accept pending
      # invitations for the user's email address.
      def after_sign_in(user)
      end

      def terminate_session
        Events.notify("session_ended") if current_session&.destroy
        forget_session
      end

      def terminate_all_sessions
        if (user = current_user)
          user.sessions.delete_all
          user.known_devices.delete_all
          user.login_challenges.live.update_all(expires_at: Time.current)
          Events.notify("all_sessions_ended", actor_id: user.id)
        end
        forget_session
      end

      def forget_session
        assign_current_session(nil)
        ::Session.forget(cookies)
        reset_session
      end

      def start_pending_challenge(issued, purpose:, email_address:)
        session[PENDING_KEY] = {
          "id" => issued.id,
          "purpose" => purpose,
          "email_address" => email_address,
          "dev_code" => (issued.code if Auth.dev_environment?)
        }.compact
      end

      def pending_challenge
        pending = session[PENDING_KEY]
        pending if pending.is_a?(Hash) && pending["id"].present?
      end

      def clear_pending_challenge
        session.delete(PENDING_KEY)
      end

      def native_app_request?
        respond_to?(:hotwire_native_app?, true) && hotwire_native_app?
      end

      def assign_current_session(new_session)
        ::Current.session = new_session
        Studio::Monitoring::Current.actor_id = new_session&.user_id if defined?(Studio::Monitoring::Current)
        new_session
      end

      def remember_return_to(path)
        if safe_return_path?(path)
          session[RETURN_TO_KEY] = path
        else
          session.delete(RETURN_TO_KEY)
        end
      end

      def safe_return_path?(path)
        path.is_a?(String) && path.start_with?("/") && !path.start_with?("//")
      end

      def same_origin_referrer_path
        uri = URI.parse(request.referer.to_s)
        uri.path if uri.host == request.host
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
