module Studio
  module Auth
    # A sign-up whose code checked out but whose account the app hasn't
    # created yet, so users never hold half-made accounts. The browser that
    # verified carries a signed cookie naming the row, like a session.
    class PendingSignUp < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      TTL = 30.days
      COOKIE_NAME = :studio_auth_pending_sign_up

      normalizes :email_address, with: ->(email_address) { TypedInput.email_address(email_address).presence }
      normalizes :time_zone, with: ->(time_zone) { time_zone if ActiveSupport::TimeZone[time_zone.to_s] }

      validates :email_address, :full_name, :expires_at, presence: true
      validates :email_address, uniqueness: true

      scope :live, -> { where(arel_table[:expires_at].gt(Time.current)) }
      scope :expired, -> { where(expires_at: ..Time.current) }

      class << self
        # One row per address: verifying again refreshes the name, time zone
        # and expiry instead of adding a second sign-up.
        def record!(email_address:, full_name:, time_zone: nil)
          pending = find_by(email_address: TypedInput.email_address(email_address)) || new(email_address: email_address)
          pending.update!(full_name: full_name, time_zone: time_zone, expires_at: TTL.from_now)
          pending
        rescue ActiveRecord::RecordNotUnique
          retry
        end

        def from_cookie(cookie_jar)
          id = cookie_jar.signed[COOKIE_NAME]
          live.find_by(id: id) if id.present?
        end

        def delete_cookie(cookie_jar)
          cookie_jar.delete(COOKIE_NAME)
        end
      end

      def write_cookie(cookie_jar)
        cookie_jar.signed[COOKIE_NAME] = {
          value: id,
          expires: expires_at,
          httponly: true,
          same_site: :lax,
          secure: !::Rails.env.local?
        }
      end
    end
  end
end
