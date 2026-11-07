require "studio/monitoring"

module Studio
  module Monitoring
    # Include in ActiveSupport::TestCase. Every test records analytics and
    # metrics in memory and sends nothing to PostHog or the database, unless
    # the test opts in with use_analytics_backends.
    #
    # Events and errors need nothing extra: Rails' assert_event_reported and
    # assert_error_reported already cover them.
    module TestHelper
      extend ActiveSupport::Concern

      Analytic = Data.define(:event_name, :actor_id, :properties)
      Metric = Data.define(:kind, :name, :value, :tags)

      class Recorder
        attr_reader :analytics, :metrics
        attr_accessor :live_backends

        def initialize
          @analytics = []
          @metrics = []
          @live_backends = []
        end

        def track(event_name, actor_id:, properties:)
          analytics << Analytic.new(event_name: event_name.to_s, actor_id: actor_id, properties: properties)
        end

        def identify(actor_id:, properties:)
          analytics << Analytic.new(event_name: "$identify", actor_id: actor_id, properties: properties)
        end

        def track_llm_generation(actor_id:, **generation)
          analytics << Analytic.new(event_name: "$ai_generation", actor_id: actor_id, properties: generation)
        end
      end

      module AnalyticsRecording
        def backends
          recorder = TestHelper.recorder
          return super if recorder.nil?

          recorder.live_backends.map { |name| Analytics::Backends::ALL.fetch(name) } + [recorder]
        end
      end

      module MetricsRecording
        def increment_counter(name, count = 1, tags: {})
          TestHelper.recorder&.metrics&.<<(Metric.new(kind: :counter, name: name, value: count, tags: tags.compact))
          super
        end

        def record_duration(name, duration_ms, tags: {})
          TestHelper.recorder&.metrics&.<<(Metric.new(kind: :duration, name: name, value: duration_ms, tags: tags.compact))
          super
        end
      end

      Analytics.singleton_class.prepend(AnalyticsRecording)
      Metrics.singleton_class.prepend(MetricsRecording)

      # Process-wide, not per thread: system tests run the app in a server
      # thread that must see the same recorder as the test.
      mattr_accessor :recorder

      included do
        setup { Studio::Monitoring::TestHelper.recorder = Recorder.new }
        teardown { Studio::Monitoring::TestHelper.recorder = nil }
      end

      # Sends analytics to real backends (:database, :posthog) for the rest of
      # the test, or only inside the block. Recording carries on either way.
      def use_analytics_backends(*names)
        names.each { |name| Analytics::Backends::ALL.fetch(name) }
        previous = monitoring_recorder.live_backends
        monitoring_recorder.live_backends = names
        return if !block_given?

        begin
          yield
        ensure
          monitoring_recorder.live_backends = previous
        end
      end

      def tracked_analytics
        monitoring_recorder.analytics
      end

      def recorded_metrics
        monitoring_recorder.metrics
      end

      # Matches a subset of properties; Regexp values match as text, like
      # assert_event_reported. With a block, only what the block tracks counts.
      def assert_analytics_tracked(event_name, actor_id: :any, properties: {}, &block)
        tracked = recording(:analytics, &block)
        match = tracked.find { |a| a.event_name == event_name.to_s && monitoring_match?(a, actor_id, properties) }
        assert match, monitoring_failure("analytics event #{event_name.inspect}", {actor_id: actor_id, properties: properties}, tracked)
        match
      end

      def assert_no_analytics_tracked(event_name = nil, &block)
        tracked = recording(:analytics, &block)
        found = event_name ? tracked.select { |a| a.event_name == event_name.to_s } : tracked
        assert_empty found, "Expected no analytics event#{" #{event_name.inspect}" if event_name}, got:\n  #{found.map(&:inspect).join("\n  ")}"
      end

      def assert_analytics_identified(actor_id: :any, properties: {}, &block)
        assert_analytics_tracked("$identify", actor_id: actor_id, properties: properties, &block)
      end

      def assert_counter_incremented(name, by: nil, tags: {}, &block)
        assert_metric(:counter, name, by, tags, &block)
      end

      def assert_duration_recorded(name, tags: {}, &block)
        assert_metric(:duration, name, nil, tags, &block)
      end

      def assert_no_metric_recorded(name, &block)
        found = recording(:metrics, &block).select { |m| m.name == name }
        assert_empty found, "Expected no metric #{name.inspect}, got:\n  #{found.map(&:inspect).join("\n  ")}"
      end

      private

      def monitoring_recorder
        TestHelper.recorder || raise("Studio::Monitoring::TestHelper is not set up for this test")
      end

      def recording(kind)
        list = monitoring_recorder.public_send(kind)
        return list if !block_given?

        start = list.size
        yield
        list.drop(start)
      end

      def assert_metric(kind, name, value, tags, &block)
        metrics = recording(:metrics, &block)
        match = metrics.find do |m|
          m.kind == kind && m.name == name && (value.nil? || m.value == value) && monitoring_subset?(m.tags, tags)
        end
        assert match, monitoring_failure("#{kind} #{name.inspect}", {value: value, tags: tags}.compact, metrics)
        match
      end

      def monitoring_match?(analytic, actor_id, properties)
        (actor_id == :any || analytic.actor_id == actor_id) && monitoring_subset?(analytic.properties, properties)
      end

      def monitoring_subset?(actual, expected)
        expected.all? do |key, value|
          name = [key, key.to_s, key.to_sym].find { |k| actual.key?(k) }
          found = name.nil? ? nil : actual[name]
          value.is_a?(Regexp) ? found.to_s.match?(value) : found == value
        end
      end

      def monitoring_failure(what, expected, recorded)
        "Expected #{what} matching #{expected.inspect}, got #{recorded.size}:\n  #{recorded.map(&:inspect).join("\n  ")}"
      end
    end
  end
end
