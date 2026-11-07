module Studio
  module Monitoring
    module Tags
      class << self
        def apply(**tags)
          tags = tags.compact.transform_values { |value| value.is_a?(Symbol) ? value.to_s : value }
          return if tags.empty?

          ::Appsignal.add_tags(tags)
          span = root_span
          span.add_attributes(tags.transform_keys(&:to_s)) if span.recording?
        end

        private

        def root_span
          span = OpenTelemetry::Instrumentation::Rack.current_span
          span.context.valid? ? span : OpenTelemetry::Trace.current_span
        end
      end
    end
  end
end
