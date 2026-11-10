module Studio
  module Auth
    class Device
      COOKIE_NAME = :studio_device

      def initialize(cookie_jar)
        @cookie_jar = cookie_jar
      end

      def token
        @cookie_jar.signed[COOKIE_NAME]
      end

      # Runs the query for a nil user too, so unknown addresses take the same time.
      def known_for?(user)
        known = KnownDevice.trusted.exists?(user_id: user&.id || Challenges::NO_USER_ID, token_digest: KnownDevice.digest_token(token.to_s))
        known && user.present? && token.present?
      end

      def ensure_token!
        assign_token if token.blank?
        token
      end

      # A device signing in for the first time gets a fresh token, so a
      # cookie planted before sign-in never becomes a known device.
      #
      # Only the sign-in that follows signing up counts as :first and sends
      # no email. Deciding by "no known devices yet" would also stay silent
      # after Sign out everywhere, which is exactly when an alert matters.
      def remember_for(user, user_agent:, ip_address:)
        ensure_token!
        if (device = KnownDevice.trusted.find_by(user_id: user.id, token_digest: KnownDevice.digest_token(token)))
          device.update_columns(last_seen_at: Time.current, user_agent: user_agent, ip_address: ip_address)
          return :known
        end

        assign_token
        first = user.created_at > CODE_TTL.ago && !KnownDevice.exists?(user_id: user.id)
        KnownDevice.create!(user: user, token_digest: KnownDevice.digest_token(token), user_agent: user_agent, ip_address: ip_address, last_seen_at: Time.current)
        first ? :first : :new
      end

      private

      def assign_token
        @cookie_jar.signed.permanent[COOKIE_NAME] = {
          value: Secrets.generate_token,
          httponly: true,
          same_site: :lax,
          secure: !::Rails.env.local?
        }
      end
    end
  end
end
