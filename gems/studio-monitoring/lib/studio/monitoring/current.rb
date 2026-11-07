module Studio
  module Monitoring
    class Current < ActiveSupport::CurrentAttributes
      attribute :request_id, :job_id, :analytics_session_id

      class << self
        def from_request(request)
          self.request_id = request.request_id
          self.analytics_session_id = request.headers["X-POSTHOG-SESSION-ID"] || posthog_cookie_session_id(request.cookies)
        end

        private

        # posthog-js sends the session header only on fetch/XHR, so page loads
        # fall back to the session it keeps in its cookie, where $sesid is
        # [last_activity_ms, id, start_ms].
        def posthog_cookie_session_id(cookies)
          posthog = Monitoring.config.posthog
          return if posthog.nil?

          cookie = cookies["ph_#{posthog.token}_posthog"]
          return if cookie.nil?

          persisted = JSON.parse(cookie)
          session = persisted["$sesid"] if persisted.is_a?(Hash)
          session[1] if session.is_a?(Array)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
