module Studio
  module Monitoring
    class Configuration
      PosthogProject = Data.define(:token, :host)
      PosthogBrowser = Data.define(:host, :ui_host, :defaults)

      # posthog-js behaviour defaults by release date. Move it forward on
      # purpose, after reading PostHog's changelog for what changed.
      POSTHOG_JS_DEFAULTS = "2026-05-30"

      # Channel actions are named by event (subscribe), not by callback
      # (subscribed) as AppSignal names them.
      HEALTH_CHECK_PATH = "/up"

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

      # Active Storage signed blob ids sit in unnamed path segments that
      # Redaction cannot see. Entries are path prefixes or Regexps.
      DEFAULT_UNTRACED_PATHS = ["/assets/", "/rails/active_storage/"].freeze

      attr_accessor :service_name, :default_properties, :untraced_paths,
        :unlogged_actions, :appsignal_ignored_paths, :log_backends, :analytics_backends,
        :posthog_masked_paths
      attr_reader :posthog, :posthog_browser

      def initialize
        @default_properties = -> { {} }
        @untraced_paths = DEFAULT_UNTRACED_PATHS.dup
        @unlogged_actions = DEFAULT_UNLOGGED_ACTIONS.dup
        @appsignal_ignored_paths = []
        @posthog_masked_paths = []
        @log_backends = [:rails, :appsignal, :posthog]
        @analytics_backends = [:posthog]
      end

      def posthog_project(token:, host:)
        raise ArgumentError, "posthog_project needs both token: and host:" if token.blank? || host.blank?

        @posthog = PosthogProject.new(token: token, host: host)
      end

      # host is where posthog-js sends events, usually a reverse proxy on the
      # app's own domain so ad blockers let them through.
      def posthog_browser_hosts(host:, ui_host:, defaults: POSTHOG_JS_DEFAULTS)
        raise ArgumentError, "posthog_browser_hosts needs both host: and ui_host:" if host.blank? || ui_host.blank?

        @posthog_browser = PosthogBrowser.new(host: host, ui_host: ui_host, defaults: defaults)
      end

      def validate!
        if service_name.blank?
          raise ArgumentError, "Studio::Monitoring needs c.service_name, set in config/initializers/monitoring.rb"
        end
        if posthog_browser && posthog.nil?
          raise ArgumentError, "Studio::Monitoring c.posthog_browser_hosts needs c.posthog_project for the token"
        end
        validate_backends!("log_backends", log_backends, EventLog::Backends::ALL)
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
