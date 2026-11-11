module Studio
  module Admin
    module AdminRoutes
      def studio_admin(&routes)
        constraints StaffConstraint do
          mount ::MissionControl::Jobs::Engine, at: "/admin/jobs", as: :admin_jobs
          mount ::Flipper::UI.app(::Flipper), at: "/admin/flipper", as: :admin_flipper
          mount ::PgHero::Engine, at: "/admin/pghero", as: :admin_pghero
          namespace(:admin, &routes) if routes
        end

        match "admin(/*path)", to: "studio/admin/fallbacks#show", via: :all, format: false
      end
    end
  end
end
