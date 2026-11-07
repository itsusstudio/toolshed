module Studio
  module Monitoring
    class Configuration
      PosthogProject = Data.define(:token, :host)

      # Channel actions are named by event (subscribe), not by callback
      # (subscribed) as AppSignal names them.
      DEFAULT_UNLOGGED_ACTIONS = [
        "Rails::HealthController#show",
        "ActiveStorage::Blobs::RedirectController#show",
        "ActiveStorage::Representations::RedirectController#show",
        "Turbo::StreamsChannel#subscribe",
        "Turbo::StreamsChannel#unsubscribe",
        "ApplicationCable::Connection#connect",
        "ApplicationCable::Connection#disconnect",
        "Rails::PwaController#service_worker",
        "Hotwire::Configurations::AndroidController#v1",
        "Hotwire::Configurations::IosController#v1",
        "Hotwire::WellKnownController#apple_app_site_association",
        "Hotwire::WellKnownController#assetlinks"
      ].freeze

      # Spans keep the raw path, so Active Storage signed blob ids would leak
      # into traces. Entries are path prefixes or Regexps.
      DEFAULT_UNTRACED_PATHS = ["/assets/", "/rails/active_storage/"].freeze

      attr_accessor :service_name, :actor_id, :tenant_id, :default_properties, :untraced_paths,
        :unlogged_actions, :log_backends, :analytics_backends
      attr_reader :posthog

      def initialize
        @actor_id = -> {}
        @tenant_id = -> {}
        @default_properties = -> { {} }
        @untraced_paths = DEFAULT_UNTRACED_PATHS.dup
        @unlogged_actions = DEFAULT_UNLOGGED_ACTIONS.dup
        @log_backends = [:rails, :appsignal, :posthog]
        @analytics_backends = [:posthog]
      end

      def posthog_project(token:, host:)
        raise ArgumentError, "posthog_project needs both token: and host:" if token.blank? || host.blank?

        @posthog = PosthogProject.new(token: token, host: host)
      end

      def validate!
        if service_name.blank?
          raise ArgumentError, "Studio::Monitoring needs c.service_name, set in config/initializers/monitoring.rb"
        end
        validate_backends!("log_backends", log_backends, Logging::Backends::ALL)
        validate_backends!("analytics_backends", analytics_backends, Analytics::Backends::ALL)
      end

      private

      def validate_backends!(setting, names, known)
        unknown = names - known.keys
        return if unknown.empty?

        raise ArgumentError, "Studio::Monitoring #{setting} has unknown #{unknown.map(&:inspect).join(", ")}; known: #{known.keys.map(&:inspect).join(", ")}"
      end
    end
  end
end
