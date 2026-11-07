module Studio
  module Monitoring
    module Analytics
      module Backends
        class Database
          def track(event_name, actor_id:, properties:)
            AnalyticsEvent.create!(
              actor_id: actor_id,
              tenant_id: Monitoring.tenant_id,
              event_name: event_name,
              properties: properties.except(:actor_id, :tenant_id)
            )
          end

          def identify(actor_id:, properties:)
          end
        end
      end
    end
  end
end
