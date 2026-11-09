module Studio
  module Monitoring
    # AppSignal bills per request and has no sampling setting, so requests we
    # don't keep are moved into a namespace listed in ignore_namespaces, which
    # the agent drops before sending. Must sit inside
    # Appsignal::Rack::RailsInstrumentation so the transaction is still open
    # when the namespace is set; the Railtie inserts it in that position.
    class RequestSampling
      DROPPED_NAMESPACE = "sampled_out"
      KEEP_RATE = 0.25
      SLOW_REQUEST_THRESHOLD_SECONDS = 0.5
      ERROR_REPORTED_KEY = :studio_monitoring_request_sampling_error_reported

      class << self
        # A handled error attaches to the request's
        # AppSignal transaction, so dropping that request would drop the error too.
        def report(*, **)
          ActiveSupport::IsolatedExecutionState[ERROR_REPORTED_KEY] = true
        end
      end

      def initialize(app)
        @app = app
      end

      def call(env)
        ActiveSupport::IsolatedExecutionState.delete(ERROR_REPORTED_KEY)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status, headers, body = @app.call(env)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

        sample(env, status.to_i, duration)
        [status, headers, body]
      end

      private

      # Monitoring must never break the response it is measuring.
      def sample(env, status, duration)
        Appsignal.set_namespace(DROPPED_NAMESPACE) if drop?(env, status, duration)
      rescue => error
        ::Rails.error.report(error, handled: true, source: self.class.name)
      end

      def drop?(env, status, duration)
        return true if env.key?(UNRECORDED_REQUEST)

        path = env["PATH_INFO"].to_s
        return true if ignored?(path)
        return false if error_reported? || status >= 500
        return true if status == 404
        return false if duration >= SLOW_REQUEST_THRESHOLD_SECONDS

        Random.rand >= KEEP_RATE
      end

      def ignored?(path)
        return true if path == Configuration::HEALTH_CHECK_PATH

        Monitoring.config.appsignal_ignored_paths.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
      end

      def error_reported?
        ActiveSupport::IsolatedExecutionState[ERROR_REPORTED_KEY] == true
      end
    end
  end
end
