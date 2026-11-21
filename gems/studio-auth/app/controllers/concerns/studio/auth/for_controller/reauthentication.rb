module Studio
  module Auth
    module ForController
      module Reauthentication
        extend ActiveSupport::Concern

        WINDOW = 10.minutes
        CONFIRMED_AT_KEY = :studio_auth_reauthenticated_at
        REQUESTED_KEY = :studio_auth_reauthentication_requested

        private

        def recently_authenticated?
          return false if current_session.nil?
          return true if current_session.signed_in_within?(WINDOW)

          session[CONFIRMED_AT_KEY].to_i > WINDOW.ago.to_i
        end

        def mark_recently_authenticated
          session[CONFIRMED_AT_KEY] = Time.current.to_i
        end

        def request_reauthentication(return_to: nil, **flash)
          store_return_path(return_to) if return_to
          session[REQUESTED_KEY] = true
          redirect_to main_app.login_path, **flash
        end

        def reauthentication_requested?
          authenticated? && session[REQUESTED_KEY].present?
        end
      end
    end
  end
end
