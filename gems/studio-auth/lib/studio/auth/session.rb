module Studio
  module Auth
    module Session
      extend ActiveSupport::Concern

      COOKIE_NAME = :session_id

      included do
        belongs_to :user, class_name: "::User"

        before_create do
          self.last_seen_at ||= Time.current
          self.authenticated_at ||= Time.current
        end

        # A NULL last_seen_at is a session from before this gem: active until
        # its first request records it, so installing the gem signs no one out.
        scope :active, -> { where(created_at: SESSION_ABSOLUTE_TIMEOUT.ago..).merge(where(last_seen_at: nil).or(where(last_seen_at: SESSION_IDLE_TIMEOUT.ago..))) }
        scope :expired, -> { where(created_at: ...SESSION_ABSOLUTE_TIMEOUT.ago).or(where(last_seen_at: ...SESSION_IDLE_TIMEOUT.ago)) }
      end

      class_methods do
        def from_cookie(cookie_jar, scope: all)
          id = id_from_cookie(cookie_jar)
          return if id.blank?

          scope.merge(active).find_by(id: id)&.tap(&:touch_last_seen)
        end

        def id_from_cookie(cookie_jar)
          cookie_jar.signed[COOKIE_NAME]
        end

        def forget(cookie_jar)
          cookie_jar.delete(COOKIE_NAME)
        end
      end

      def remember_in(cookie_jar)
        cookie_jar.signed[COOKIE_NAME] = {
          value: id,
          expires: absolute_expires_at,
          httponly: true,
          same_site: :lax,
          secure: !::Rails.env.local?
        }
      end

      def absolute_expires_at
        created_at + SESSION_ABSOLUTE_TIMEOUT
      end

      def recently_authenticated?(within: REAUTHENTICATION_WINDOW)
        authenticated_at.present? && authenticated_at > within.ago
      end

      def reauthenticated!
        update_column(:authenticated_at, Time.current)
      end

      def touch_last_seen
        return if last_seen_at && last_seen_at > SESSION_TOUCH_THROTTLE.ago

        update_column(:last_seen_at, Time.current)
      end
    end
  end
end
