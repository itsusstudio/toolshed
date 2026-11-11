module Studio
  module Auth
    module ForSession
      extend ActiveSupport::Concern

      COOKIE_NAME = :session_id
      SESSION_TOUCH_THROTTLE = 1.hour

      included do
        belongs_to :user, class_name: "::User"

        before_create do
          self.last_seen_at ||= Time.current
        end

        # A NULL last_seen_at is a session from before this gem; it stays
        # active until its first request records one.
        scope :active, -> {
          not_idle = where(last_seen_at: nil).or(where(last_seen_at: Auth.config.session_idle_timeout.ago..))
          where(created_at: Auth.config.session_absolute_timeout.ago..).merge(not_idle)
        }
        scope :expired, -> {
          where(created_at: ...Auth.config.session_absolute_timeout.ago)
            .or(where(last_seen_at: ...Auth.config.session_idle_timeout.ago))
        }
      end

      def signed_in_within?(duration)
        created_at >= duration.ago
      end

      class_methods do
        def from_cookie(cookie_jar, scope: all)
          id = id_from_cookie(cookie_jar)
          return if id.blank?

          found = scope.merge(active).find_by(id: id)
          return if found.nil? || !found.user.can_sign_in?

          found.tap(&:touch_last_seen)
        end

        def id_from_cookie(cookie_jar)
          cookie_jar.signed[COOKIE_NAME]
        end

        def delete_cookie(cookie_jar)
          cookie_jar.delete(COOKIE_NAME)
        end
      end

      def write_cookie(cookie_jar)
        cookie_jar.signed[COOKIE_NAME] = {
          value: id,
          expires: cookie_expires_at,
          httponly: true,
          same_site: :lax,
          secure: !::Rails.env.local?
        }
      end

      def cookie_expires_at
        created_at + Auth.config.session_absolute_timeout
      end

      def touch_last_seen
        return if last_seen_at && last_seen_at > SESSION_TOUCH_THROTTLE.ago

        update_column(:last_seen_at, Time.current)
      end
    end
  end
end
