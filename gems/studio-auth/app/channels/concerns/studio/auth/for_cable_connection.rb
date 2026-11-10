module Studio
  module Auth
    module ForCableConnection
      extend ActiveSupport::Concern

      included do
        identified_by :current_session
      end

      def connect
        self.current_session = ::Session.from_cookie(cookies) || reject_unauthorized_connection
      end

      def current_user
        current_session&.user
      end
    end
  end
end
