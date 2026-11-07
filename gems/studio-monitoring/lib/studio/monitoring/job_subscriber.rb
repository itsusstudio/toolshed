module Studio
  module Monitoring
    class JobSubscriber
      def call(event)
        job = event.payload[:job]
        # Framework jobs (Turbo broadcasts, Solid Cable trims) would flood logs.
        return if !defined?(::ApplicationJob) || !job.is_a?(::ApplicationJob)

        error = event.payload[:exception_object]
        properties = {
          job_id: job.job_id,
          queue: job.queue_name,
          executions: job.executions,
          duration: event.duration.round(2),
          success: error.nil?,
          message: error&.class&.name
        }
        level = error ? :log_error : :log_info
        Logging.public_send(level, job.class, "job_performed", properties: properties)
      end
    end
  end
end
