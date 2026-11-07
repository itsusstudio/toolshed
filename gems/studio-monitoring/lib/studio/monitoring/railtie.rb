module Studio
  module Monitoring
    class Railtie < ::Rails::Railtie
      config.after_initialize do
        Events.info("monitoring_configured", **Monitoring.summary)
      end

      initializer "studio_monitoring.current" do
        ActiveSupport.on_load(:action_controller) do
          prepend_before_action do
            Current.from_request(request)
            Redaction.mask_current_span(request)
          end
        end
        ActiveSupport.on_load(:active_job) do
          before_perform { Current.job_id = job_id }
        end
      end

      # Runs after config/initializers so the app's configure block is in, and
      # before after_initialize, where lograge and posthog-rails read their
      # settings.
      initializer "studio_monitoring.setup", after: :load_config_initializers do |app|
        config = Monitoring.config
        config.validate!

        ::Rails.event.subscribe(EventLog::Subscriber.new)
        ::Rails.error.add_middleware(->(_error, context:, **) { Monitoring.default_properties.merge(context) })

        Telemetry.setup(config)
        PosthogClient.setup(config)
        RequestLog.setup(app, config)
        JobLog.setup
      end
    end
  end
end
