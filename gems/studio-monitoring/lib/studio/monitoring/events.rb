module Studio
  module Monitoring
    # The studio interface to Rails.event, one method per log level. Events are
    # logged by EventLog::Subscriber.
    #
    # Names are the flow in snake_case, object first (checkout_return,
    # job_performed), never prose. Log search and dashboards filter on the name,
    # so renaming one breaks every query behind it.
    module Events
      class << self
        # Only reported in local environments, as Rails.event.debug is.
        def debug(name, **payload)
          ::Rails.event.debug(name, caller_depth: 2, **payload, level: :debug)
        end

        # caller_depth: 2 makes Rails record the app's call site as the source,
        # not this method.
        [:info, :warn, :error].each do |level|
          define_method(level) do |name, **payload|
            ::Rails.event.notify(name, caller_depth: 2, **payload, level: level)
          end
        end
      end
    end
  end
end
