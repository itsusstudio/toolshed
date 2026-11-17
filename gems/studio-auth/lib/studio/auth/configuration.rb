module Studio
  module Auth
    class Configuration
      class Error < StandardError; end

      REQUIRED = [
        :app_name, :mail_from,
        :mail_address, :terms_url, :privacy_url
      ].freeze

      # mail_address is the sender's name, street and city, one line each, at
      # the foot of every mail; terms_url and privacy_url are linked there and
      # under the sign-in pages.
      attr_accessor(*REQUIRED)

      SESSION_LIMITS = [:session_idle_timeout, :session_absolute_timeout].freeze

      attr_accessor(*SESSION_LIMITS)

      # page_layout is the app's Uniform document layout the sign-in pages
      # render inside; wordmark is the app name's voice, "serif" or "sans".
      attr_writer :page_layout, :wordmark

      # true takes new accounts at /signup; false is invite-only, and an
      # address with no account gets an error on the sign-in page. No
      # default: an app has to choose.
      attr_accessor :sign_up

      def page_layout = @page_layout || "application"

      def wordmark = @wordmark || "serif"

      def validate_config!
        missing = REQUIRED.select { |setting| public_send(setting).blank? }
        missing += SESSION_LIMITS.reject { |setting| public_send(setting).is_a?(ActiveSupport::Duration) }
        if missing.any?
          settings = missing.map { "c.#{it}" }.join(", ")
          raise Error, "studio-auth: set #{settings} in config/initializers/studio_auth.rb " \
            "(session limits take a duration, e.g. 30.days)"
        end

        if ![true, false].include?(sign_up)
          raise Error, "studio-auth: set c.sign_up to true or false in config/initializers/studio_auth.rb"
        end

        if !["serif", "sans"].include?(wordmark.to_s)
          raise Error, "studio-auth: c.wordmark is \"serif\" or \"sans\", not #{wordmark.inspect}"
        end

        AppReviewAccounts.validate_config!
      end
    end
  end
end
