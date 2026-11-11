module Studio
  module Admin
    class Engine < ::Rails::Engine
      config.mission_control.jobs.base_controller_class = "AdminBaseController"
      config.mission_control.jobs.http_basic_auth_enabled = false

      initializer "studio_admin.routes" do
        ActionDispatch::Routing::Mapper.include AdminRoutes
      end

      initializer "studio_admin.validate", after: :load_config_initializers do
        Admin.config.validate_config!
      end
    end
  end
end
