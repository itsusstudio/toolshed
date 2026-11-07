module Studio
  module Monitoring
    module Analytics
      class << self
        def backends
          Monitoring.config.analytics_backends.map { |name| Backends::ALL.fetch(name) }
        end

        def track(event_name, actor_id: Monitoring.actor_id, properties: {})
          properties = Monitoring.default_properties.merge(properties).compact

          each_backend(event_name) do |backend|
            backend.track(event_name, actor_id: actor_id, properties: properties)
          end
        end

        # Person properties must stay non-identifying: no email or name.
        def identify(actor_id: Monitoring.actor_id, properties: {})
          each_backend("identify") { |backend| backend.identify(actor_id: actor_id, properties: properties.compact) }
        end

        def track_llm_generation(actor_id: Monitoring.actor_id, **generation)
          each_backend("llm_generation") do |backend|
            next if !backend.respond_to?(:track_llm_generation)

            backend.track_llm_generation(actor_id: actor_id, **generation)
          end
        end

        private

        def each_backend(event_name)
          backends.each do |backend|
            yield backend
          rescue => error
            Events.warn("analytics_backend", success: false, message: error.class.name,
              backend: backend.class.name, event_name: event_name)
          end
        end
      end
    end
  end
end
