module Studio
  module Monitoring
    module Posthog
      EXCLUDED_EXCEPTIONS = [
        "ActionController::RoutingError",
        "ActionController::UnknownFormat",
        "ActionController::UnknownHttpMethod",
        "ActionController::BadRequest",
        "ActionController::InvalidAuthenticityToken",
        "ActionDispatch::Http::MimeNegotiation::InvalidType",
        "ActionDispatch::Http::Parameters::ParseError",
        "ActionView::MissingTemplate",
        "Rack::Multipart::BoundaryTooLongError",
        "Rack::QueryParser::InvalidParameterError"
      ].freeze

      class << self
        def setup(config)
          ::PostHog::Rails.configure do |posthog|
            posthog.auto_capture_exceptions = true
            posthog.report_rescued_exceptions = true
            posthog.auto_instrument_active_job = true
            posthog.excluded_exceptions = EXCLUDED_EXCEPTIONS.dup
          end
          return if config.posthog.nil?

          # The one client for the process: posthog-ruby drops events when
          # several clients share a token.
          ::PostHog.init do |posthog|
            posthog.api_key = config.posthog.token
            posthog.host = config.posthog.host
            posthog.on_error = proc { |status, error|
              Logging.log_warn(::PostHog, "posthog_send",
                properties: {success: false, message: error.to_s, status: status})
            }
            # Server events come from the host's IP, so GeoIP would stamp them,
            # and the person, with the data centre's city.
            posthog.before_send = proc { |event|
              event[:properties] = (event[:properties] || {}).merge("$geoip_disable" => true)
              event
            }
          end
        end
      end
    end
  end
end
