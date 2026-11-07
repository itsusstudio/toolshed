module Studio
  module Monitoring
    class Railtie < ::Rails::Railtie
      config.after_initialize do
        Logging.log_info(Monitoring, "monitoring_configured", properties: Monitoring.summary)
      end

      initializer "studio_monitoring.current" do
        ActiveSupport.on_load(:action_controller) do
          prepend_before_action { Current.from_request(request) }
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

        Telemetry.setup(config)
        Posthog.setup(config)
        Lograge.setup(app, config)
        if !::Rails.env.local?
          ActiveSupport::Notifications.subscribe("perform.active_job", JobSubscriber.new)
        end
      end
    end
  end
end
