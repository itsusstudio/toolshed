module Studio
  module Auth
    class LoginChallenge < ActiveRecord::Base # standard:disable Rails/ApplicationRecord -- a gem has no ApplicationRecord
      PURPOSES = ["sign_in", "reauthentication"].freeze

      include UserReference

      validates :purpose, inclusion: {in: PURPOSES}

      scope :live, -> { where(consumed_at: nil).where(arel_table[:expires_at].gt(Time.current)) }
      scope :within_failure_window, -> { where(created_at: FAILURE_WINDOW.ago..) }
      scope :purgeable, -> { where(created_at: ...FAILURE_WINDOW.ago) }

      class << self
        def digest_code(code)
          Secrets.digest("login_challenge", code)
        end
      end

      def decoy?
        user_id.nil?
      end

      def finished?
        consumed_at.present? || expires_at <= Time.current
      end

      def from?(device)
        device.token.present? && device_token_digest.present? &&
          ActiveSupport::SecurityUtils.secure_compare(device_token_digest, KnownDevice.digest_token(device.token))
      end

      def exhausted?
        failed_attempts >= CODE_MAX_ATTEMPTS
      end

      # The digest is compared for decoys too, so they cost the same time;
      # a decoy never matches.
      def code_matches?(code)
        matches = Secrets.matches?(code_digest, "login_challenge", code)
        matches && !decoy?
      end
    end
  end
end
