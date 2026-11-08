module Studio
  module Monitoring
    # posthog-js for the pages: product analytics, session replay and browser
    # errors, identified with the same distinct id as the server's events.
    module BrowserAnalytics
      SNIPPET = File.read(File.expand_path("browser_analytics.js", __dir__)).freeze

      module Helper
        # properties are registered on every browser event, so keep them low
        # cardinality and free of personal data.
        def studio_analytics_tag(properties: {})
          project = Monitoring.config.posthog
          browser = Monitoring.config.posthog_browser
          return if project.nil? || browser.nil?

          tag.script(SNIPPET.html_safe, nonce: content_security_policy_nonce, data: {
            posthog_token: project.token,
            posthog_host: browser.host,
            posthog_ui_host: browser.ui_host,
            posthog_defaults: browser.defaults,
            posthog_masked_paths: Monitoring.config.posthog_masked_paths.to_json,
            posthog_user_id: Current.actor_id,
            posthog_tenant_id: Current.tenant_id,
            posthog_properties: properties.compact.to_json
          })
        end
      end
    end
  end
end
