module Studio
  module Auth
    module ForController
      # Who is signed in, and sending everyone else to sign in.
      module Authentication
        extend ActiveSupport::Concern

        included do
          before_action :require_authentication
          helper_method :authenticated?, :current_user, :current_session
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

        def native_app_request?
          respond_to?(:hotwire_native_app?, true) && hotwire_native_app?
        end

        def assign_current_session(new_session)
          ::Current.session = new_session
          Studio::Monitoring::Current.actor_id = new_session&.user_id if defined?(Studio::Monitoring::Current)
          new_session
        end
      end
    end
  end
end
