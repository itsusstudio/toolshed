module Studio
  module Monitoring
    # Log search and dashboards filter on the event name, so renaming one
    # breaks every query behind it.
    module Events
      class << self
        def debug(name, **payload)
          ::Rails.event.debug(name, caller_depth: 2, **Redaction.plain(payload), level: :debug)
        end

        # caller_depth: 2 makes Rails record the app's call site as the source,
        # not this method.
        [:info, :warn, :error].each do |level|
          define_method(level) do |name, **payload|
            ::Rails.event.notify(name, caller_depth: 2, **Redaction.plain(payload), level: level)
          end
        end
      end
    end
  end
end
