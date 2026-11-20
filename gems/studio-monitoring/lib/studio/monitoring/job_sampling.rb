module Studio
  module Monitoring
    # Jobs never pass through RequestSampling, and a backfill can enqueue
    # thousands of them in a day, each billed by AppSignal as a request.
    module JobSampling
      SLOW_JOB_THRESHOLD_SECONDS = 2.0
      DEPTH_KEY = :studio_monitoring_job_sampling_depth

      class << self
        def around(_job)
          depth = ActiveSupport::IsolatedExecutionState[DEPTH_KEY].to_i
          ActiveSupport::IsolatedExecutionState[DEPTH_KEY] = depth + 1
          reported_before = ActiveSupport::IsolatedExecutionState.delete(RequestSampling::ERROR_REPORTED_KEY)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          failed = true
          yield
          failed = false
        ensure
          reported = ActiveSupport::IsolatedExecutionState[RequestSampling::ERROR_REPORTED_KEY] == true
          ActiveSupport::IsolatedExecutionState[RequestSampling::ERROR_REPORTED_KEY] = true if reported_before
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          ActiveSupport::IsolatedExecutionState[DEPTH_KEY] = depth
          # A nested perform_now shares its parent's transaction, so only the outermost job decides.
          sample(failed || reported, duration) if depth.zero?
        end

        private

        # Monitoring must never break the job it is measuring.
        def sample(kept, duration)
          return if kept || duration >= SLOW_JOB_THRESHOLD_SECONDS
          return if !performed_by_queue?
          return if Random.rand < RequestSampling::KEEP_RATE

          Appsignal.set_namespace(RequestSampling::DROPPED_NAMESPACE)
        rescue => error
          ::Rails.error.report(error, handled: true, source: name)
        end

        # perform_now inside a request shares the request's transaction, and
        # tagging it would drop the request.
        def performed_by_queue?
          Appsignal::Transaction.current? &&
            Appsignal::Transaction.current.namespace == Appsignal::Transaction::BACKGROUND_JOB
        end
      end
    end
  end
end
