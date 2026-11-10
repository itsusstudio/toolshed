require "rails"
require "active_support"
require "active_support/core_ext"
require "openssl"
require "valid_email2"

require_relative "auth/configuration"
require_relative "auth/typed_input"
require_relative "auth/events"
require_relative "auth/secrets"
require_relative "auth/app_review_accounts"
require_relative "auth/routes"

module Studio
  module Auth
    LOGIN_CODE_TTL = 10.minutes
    LOGIN_CODE_MAX_ATTEMPTS = 5
    LOGIN_CODE_RESEND_INTERVAL = 60.seconds

    LOCKOUT_WINDOW = 24.hours
    LOCKOUT_WRONG_CODES = 10
    LOCKOUT_DURATION = 1.hour
    APP_REVIEW_LOCKOUT_WRONG_CODES = 20
    SIGN_IN_IP_HOURLY_LIMIT = 30

    KNOWN_DEVICE_TRUST = 90.days

    # Decoys have no user, but must run the same queries as a real address
    # so response time doesn't reveal which addresses have accounts. No
    # user has id 0; a nil id would query IS NULL and scan every decoy.
    DECOY_USER_ID = 0
    SESSION_TOUCH_THROTTLE = 1.hour

    MAIL_QUEUE = :less_than_five_seconds

    FILTER_PARAMETERS = [/\Acode\z/].freeze

    autoload :SecurityTests, "studio/auth/security_tests"

    class << self
      def table_name_prefix = "studio_auth_"

      def configure
        yield config
        config
      end

      def config
        @config ||= Configuration.new
      end
    end
  end
end

require_relative "auth/engine"
