module Studio
  module Admin
    class FallbacksController < ::AdminBaseController
      def show
        redirect_to admin_root_path
      end
    end
  end
end
