module Studio
  module Auth
    module ForController
      # Where to send someone once they sign in.
      module ReturnPath
        extend ActiveSupport::Concern

        private

        def after_authentication_path
          session.delete(RETURN_TO_KEY) || main_app.root_path
        end

        def store_return_path(path)
          if safe_return_path?(path)
            session[RETURN_TO_KEY] = path
          else
            session.delete(RETURN_TO_KEY)
          end
        end

        def safe_return_path?(path)
          path.is_a?(String) && path.start_with?("/") && !path.start_with?("//")
        end
      end
    end
  end
end
