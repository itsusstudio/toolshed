module Studio
  # Dashboards chart by name, so renaming a metric orphans its old series.
  module Monitoring
    module Metrics
      INSTRUMENTS = Concurrent::Map.new

      class << self
        # Every unique tag combination is its own series, so tags must stay low
        # cardinality. Unbounded values (ids, URLs) belong in log properties.
        def increment_counter(name, count = 1, tags: {})
          instrument(:counter, name).add(count, attributes: attributes(tags))
        end

        def record_duration(name, duration_ms, tags: {})
          instrument(:histogram, name).record(duration_ms, attributes: attributes(tags))
        end

        private

        def instrument(kind, name)
          INSTRUMENTS.compute_if_absent([meter, kind, name]) do
            (kind == :counter) ? meter.create_counter(name) : meter.create_histogram(name, unit: "ms")
          end
        end

        def attributes(tags)
          tags.compact.to_h { |key, value| [key.to_s, value.to_s] }
        end

        def meter
          OpenTelemetry.meter_provider.meter(Monitoring.config.service_name)
        end
      end
    end
  end
end
