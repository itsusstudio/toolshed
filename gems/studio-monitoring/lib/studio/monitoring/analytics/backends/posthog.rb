module Studio
  module Monitoring
    module Analytics
      module Backends
        class Posthog
          # Without a distinct_id PostHog records the event as personless, which
          # is what logged-out visitors should be.
          def track(event_name, actor_id:, properties:)
            return if client.nil?

            properties = properties.merge("$session_id" => session_id).compact
            client.capture({distinct_id: actor_id&.to_s, event: event_name, properties: properties, groups: groups}.compact)
          end

          def identify(actor_id:, properties:)
            return if client.nil?

            client.identify(distinct_id: actor_id.to_s, properties: properties)
          end

          def track_llm_generation(actor_id:, kind:, model:, ok:, error_code:, duration_ms:,
            input_tokens:, output_tokens:, cache_read_tokens:, cache_write_tokens:, provider: "anthropic")
            return if client.nil?

            properties = {
              "$ai_trace_id" => Current.request_id || Current.job_id || SecureRandom.uuid,
              "$ai_session_id" => session_id,
              "$session_id" => session_id,
              "$ai_span_name" => kind,
              "$ai_model" => model,
              "$ai_provider" => provider,
              "$ai_latency" => duration_ms / 1000.0,
              "$ai_is_error" => !ok,
              "$ai_error" => error_code,
              "$ai_input_tokens" => input_tokens,
              "$ai_output_tokens" => output_tokens,
              "$ai_cache_read_input_tokens" => cache_read_tokens,
              "$ai_cache_creation_input_tokens" => cache_write_tokens
            }.compact
            client.capture({distinct_id: actor_id&.to_s, event: "$ai_generation", properties: properties, groups: groups}.compact)
          end

          private

          def groups
            tenant_id = Monitoring.tenant_id
            {tenant: tenant_id.to_s} if tenant_id
          end

          def session_id
            Current.analytics_session_id
          end

          def client
            ::PostHog if ::PostHog.initialized?
          end
        end
      end
    end
  end
end
