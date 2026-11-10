module Studio
  module Auth
    class DeviceCookie
      COOKIE_NAME = :studio_auth_device

      def initialize(cookie_jar)
        @cookie_jar = cookie_jar
      end

      def device_token
        @cookie_jar.signed[COOKIE_NAME]
      end

      def trusted_for?(user)
        user_id = user&.id || LoginCode::DECOY_USER_ID
        known_device = KnownDevice.trusted.exists?(user_id: user_id, device_token_digest: digest)
        known_device && user.present? && device_token.present?
      end

      def ensure_device_token!
        assign_device_token if device_token.blank?
      end

      # A device signing in for the first time gets a fresh device token, so a
      # cookie planted before sign-in never becomes a known device.
      def trust_for(user, user_agent:, ip_address:)
        latest_visit = {user_agent: user_agent, ip_address: ip_address, last_seen_at: Time.current}

        known_device = KnownDevice.trusted.find_by(user_id: user.id, device_token_digest: digest)
        if known_device
          known_device.update_columns(latest_visit)
          return
        end

        assign_device_token
        KnownDevice.create!(user: user, device_token_digest: digest, **latest_visit)
      end

      private

      def digest
        KnownDevice.digest(device_token.to_s)
      end

      def assign_device_token
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
