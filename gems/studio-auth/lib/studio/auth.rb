require "ipaddr"
require "rails"
require "active_support"
require "active_support/core_ext"
require "openssl"

require_relative "auth/configuration"
require_relative "auth/events"
require_relative "auth/secrets"
require_relative "auth/review_accounts"
require_relative "auth/deliverability"
require_relative "auth/lockout"
require_relative "auth/locales"
require_relative "auth/user_reference"
require_relative "auth/user"
require_relative "auth/session"
require_relative "auth/device"
require_relative "auth/controller"
require_relative "auth/routes"

module Studio
  module Auth
    CODE_TTL = 10.minutes
    CODE_MAX_ATTEMPTS = 5
    CODE_RESEND_INTERVAL = 60.seconds

    FAILURE_WINDOW = 24.hours
    FAILURE_LIMIT = 10
    LOCK_DURATION = 1.hour
    REVIEW_ACCOUNT_FAILURE_LIMIT = 20
    SIGN_IN_IP_HOURLY_LIMIT = 30

    SESSION_IDLE_TIMEOUT = 30.days
    SESSION_ABSOLUTE_TIMEOUT = 90.days
    SESSION_TOUCH_THROTTLE = 1.hour
    REAUTHENTICATION_WINDOW = 15.minutes

    MAIL_QUEUE = :less_than_five_seconds
    INVISIBLE_MARKS = /[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]/

    FILTER_PARAMETERS = [/\Acode\z/].freeze

    autoload :LoginChallenge, "studio/auth/login_challenge"
    autoload :KnownDevice, "studio/auth/known_device"
    autoload :Challenges, "studio/auth/challenges"
    autoload :Mailer, "studio/auth/mailer"
    autoload :MailDeliveryJob, "studio/auth/mail_delivery_job"
    autoload :PurgeExpiredJob, "studio/auth/purge_expired_job"
    autoload :DeviceDescription, "studio/auth/device_description"
    autoload :BaseController, "studio/auth/base_controller"
    autoload :SignInsController, "studio/auth/sign_ins_controller"
    autoload :SignInCodesController, "studio/auth/sign_in_codes_controller"
    autoload :ReauthenticationsController, "studio/auth/reauthentications_controller"
    autoload :ReauthenticationCodesController, "studio/auth/reauthentication_codes_controller"
    autoload :SecurityTests, "studio/auth/security_tests"

    class << self
      def table_name_prefix = "studio_auth_"

      # One IPv6 customer usually holds a whole /64, so per-IP limits count
      # the /64; otherwise each of its addresses would get a fresh limit.
      def rate_limit_key(ip_address)
        address = IPAddr.new(ip_address.to_s)
        (address.ipv6? && !address.ipv4_mapped?) ? address.mask(64).to_s : address.to_s
      rescue IPAddr::InvalidAddressError
        ip_address.to_s
      end

      def configure
        yield config
        config
      end

      def config
        @config ||= Configuration.new
      end

      def dev_environment?
        ::Rails.env.development?
      end

      # Phones with Arabic, Persian or Thai keyboards type native digits,
      # a full-width @, and invisible direction or zero-width marks. Fold
      # them to the plain address before any lookup or check.
      def normalize_email(email_address)
        ascii_digits(email_address.to_s.scrub("").unicode_normalize(:nfkc))
          .gsub(INVISIBLE_MARKS, "")
          .strip.downcase
      end

      # Ruby's \D counts Arabic-Indic or Thai digits as non-digits, so map
      # them before stripping anything from a typed code.
      def ascii_digits(value)
        value.to_s.scrub("").gsub(/\p{Nd}/) { |digit| ascii_digit(digit) }
      end

      private

      # Unicode lays each script's decimal digits out as a run of ten, zero
      # first, so a digit's value is its distance from the start of its run.
      def ascii_digit(digit)
        return digit if digit.ascii_only?

        zero = digit.ord
        zero -= 1 while digit.ord - zero < 9 && (zero - 1).chr(Encoding::UTF_8).match?(/\p{Nd}/)
        (digit.ord - zero).to_s
      end
    end
  end
end

require_relative "auth/railtie"
