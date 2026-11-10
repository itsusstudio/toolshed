module Studio
  module Auth
    module Secrets
      KEY_SALT = "studio-auth"

      class << self
        # A keyed hash, not bcrypt: six digits are a million guesses, which a
        # slow hash only delays offline. Without secret_key_base a leaked
        # digest cannot be checked at all.
        def digest(purpose, value)
          OpenSSL::HMAC.hexdigest("SHA256", hmac_key, "#{purpose}:#{value}")
        end

        def matches?(digest, purpose, value)
          digest.present? && ActiveSupport::SecurityUtils.secure_compare(digest, digest(purpose, value))
        end

        # Codes travel to the mail job encrypted, so they never sit in plain
        # text in the job table or in Active Job's argument logs.
        def encrypt(value)
          encryptor.encrypt_and_sign(value, expires_in: CODE_TTL)
        end

        def decrypt(value)
          encryptor.decrypt_and_verify(value)
        rescue ActiveSupport::MessageEncryptor::InvalidMessage
          nil
        end

        def generate_code
          SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
        end

        def generate_token
          SecureRandom.base58(32)
        end

        private

        def hmac_key
          @hmac_key ||= key_generator.generate_key("#{KEY_SALT} hmac", 32)
        end

        def encryptor
          @encryptor ||= ActiveSupport::MessageEncryptor.new(key_generator.generate_key("#{KEY_SALT} encrypt", 32))
        end

        def key_generator
          ::Rails.application.key_generator
        end
      end
    end
  end
end
