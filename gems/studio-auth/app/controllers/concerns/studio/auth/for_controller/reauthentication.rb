module Studio
  module Auth
    module ForController
      module Reauthentication
        extend ActiveSupport::Concern

        WINDOW = 10.minutes
        CONFIRMED_AT_KEY = :studio_auth_reauthenticated_at

        private

        def recently_authenticated?
          return false if current_session.nil?
          return true if current_session.signed_in_within?(WINDOW)

          session[CONFIRMED_AT_KEY].to_i > WINDOW.ago.to_i
        end

        def mark_recently_authenticated
          session[CONFIRMED_AT_KEY] = Time.current.to_i
        end
      end
    end
  end
end
