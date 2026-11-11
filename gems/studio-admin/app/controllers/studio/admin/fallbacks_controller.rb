module Studio
  module Admin
    class FallbacksController < ::AdminBaseController
      def show
        raise ActionController::RoutingError, "Not Found"
      end
    end
  end
end
