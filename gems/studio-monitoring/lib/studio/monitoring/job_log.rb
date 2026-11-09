module Studio
  module Monitoring
    module JobLog
      class << self
        def setup
          return if ::Rails.env.local?

          ActiveSupport::Notifications.subscribe("perform_start.active_job") { |event| record_queue_wait(event.payload[:job]) }
          ActiveSupport::Notifications.subscribe("perform.active_job", self)
        end

        def call(event)
          job = event.payload[:job]
          error = event.payload[:exception_object]

          # Metrics cover framework jobs too: mail delivery and Turbo broadcasts
          # wait in the same queues, and a series costs nothing per job.
          Metrics.record_duration("job.duration", event.duration, tags: {job: job.class.name, queue: job.queue_name, ok: error.nil?})

          # Framework jobs (Turbo broadcasts, Solid Cable trims) would flood logs.
          return if !defined?(::ApplicationJob) || !job.is_a?(::ApplicationJob)

          Events.public_send(error ? :error : :info, "job_performed",
            source: job.class.name,
            job_id: job.job_id,
            queue: job.queue_name,
            executions: job.executions,
            duration: event.duration.round(2),
            success: error.nil?,
            message: error&.class&.name)
        end

        # Measured from when the job was due, so a retry's backoff or a
        # set(wait:) doesn't count as waiting.
        def record_queue_wait(job)
          due_at = job.scheduled_at || job.enqueued_at
          return if due_at.nil?

          wait_ms = [(Time.current - due_at) * 1000, 0].max
          Metrics.record_duration("job.queue_wait", wait_ms, tags: {queue: job.queue_name})
        end
      end
    end
  end
end
