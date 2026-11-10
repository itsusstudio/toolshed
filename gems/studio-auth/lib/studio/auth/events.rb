module Studio
  module Auth
    module Events
      class << self
        def notify(name, **payload)
          ::Rails.event.notify("authentication.#{name}", **payload)
        end
      end
    end
  end
end
