module Studio
  module Monitoring
    module Lograge
      class << self
        def setup(app, config)
          lograge = app.config.lograge
          lograge.enabled = !::Rails.env.local?
          lograge.ignore_actions = config.unlogged_actions
          lograge.custom_options = custom_options(ActiveSupport::ParameterFilter.new(app.config.filter_parameters))
          return if !lograge.enabled

          lograge.keep_original_rails_log = true
          lograge.formatter = ::Lograge::Formatters::Raw.new
          lograge.logger = LogrageLogger.new
        end

        private

        def custom_options(param_filter)
          lambda do |event|
            params = event.payload[:params]&.except("controller", "action")
            {
              params: params && param_filter.filter(params).to_json,
              host: event.payload[:host],
              cf_ray: event.payload[:request]&.get_header("HTTP_CF_RAY"),
              exception: event.payload[:exception]&.first,
              exception_message: event.payload[:exception_object]&.message
            }.compact
          end
        end
      end
    end
  end
end
