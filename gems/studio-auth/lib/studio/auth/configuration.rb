module Studio
  module Auth
    class Configuration
      class Error < StandardError; end

      REQUIRED = [
        :app_name, :mail_from, :support_email,
        :mail_logo_url, :terms_url, :privacy_url
      ].freeze

      # mail_logo_url is the absolute URL of the app's full logo, shown atop
      # the HTML mail; terms_url and privacy_url are linked from its footer.
      attr_accessor(*REQUIRED)

      SESSION_LIMITS = [:session_idle_timeout, :session_absolute_timeout].freeze

      attr_accessor(*SESSION_LIMITS)

      def validate_config!
        missing = REQUIRED.select { |setting| public_send(setting).blank? }
        missing += SESSION_LIMITS.reject { |setting| public_send(setting).is_a?(ActiveSupport::Duration) }
        if missing.any?
          settings = missing.map { "c.#{it}" }.join(", ")
          raise Error, "studio-auth: set #{settings} in config/initializers/studio_auth.rb " \
            "(session limits take a duration, e.g. 30.days)"
        end

        scheme = ::Rails.env.production? ? "https" : "http"
        if !mail_logo_url.to_s.start_with?(scheme)
          raise Error, "studio-auth: c.mail_logo_url must be a full #{scheme} URL; " \
            "mail clients can't load #{mail_logo_url}"
        end

        AppReviewAccounts.validate_config!
      end
    end
  end
end
