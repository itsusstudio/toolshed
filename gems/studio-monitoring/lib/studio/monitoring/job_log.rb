module Studio
  module Monitoring
    # One job_performed event per app job.
    module JobLog
      class << self
        def setup
          ActiveSupport::Notifications.subscribe("perform.active_job", self) if !::Rails.env.local?
        end

        def call(event)
          job = event.payload[:job]
          # Framework jobs (Turbo broadcasts, Solid Cable trims) would flood logs.
          return if !defined?(::ApplicationJob) || !job.is_a?(::ApplicationJob)

          error = event.payload[:exception_object]
          Events.public_send(error ? :error : :info, "job_performed",
            source: job.class.name,
            job_id: job.job_id,
            queue: job.queue_name,
            executions: job.executions,
            duration: event.duration.round(2),
            success: error.nil?,
            message: error&.class&.name)
        end
      end
    end
  end
end
