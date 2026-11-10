module Studio
  module Auth
    module Routes
      # Belly's shipped iOS and Android builds recognize /login and /verify as
      # auth screens, so these paths must not change.
      def studio_auth
        scope module: "studio/auth" do
          get "login", to: "sign_ins#new", as: :login
          post "login", to: "sign_ins#create"
          get "verify", to: "sign_in_codes#new", as: :verify
          post "verify", to: "sign_in_codes#create"
          delete "logout", to: "sign_ins#destroy", as: :logout
          delete "logout/everywhere", to: "sign_ins#destroy_all", as: :logout_everywhere
        end
      end
    end
  end
end
