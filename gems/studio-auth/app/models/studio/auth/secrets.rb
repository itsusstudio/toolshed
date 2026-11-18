module Studio
  module Auth
    module Secrets
      KEY_PURPOSE = "studio-auth"

      class << self
        def digest(purpose, value)
          OpenSSL::HMAC.hexdigest("SHA256", hmac_key, "#{purpose}:#{value}")
        end

        def matches?(digest, purpose, value)
          digest.present? && ActiveSupport::SecurityUtils.secure_compare(digest, digest(purpose, value))
        end

        def encrypt(value)
          encryptor.encrypt_and_sign(value, expires_in: LoginCode::TTL)
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
          @hmac_key ||= key_generator.generate_key("#{KEY_PURPOSE} hmac", 32)
        end

        def encryptor
          @encryptor ||= ActiveSupport::MessageEncryptor.new(key_generator.generate_key("#{KEY_PURPOSE} encrypt", 32))
        end

        def key_generator
          ::Rails.application.key_generator
        end
      end
    end
  end
end
