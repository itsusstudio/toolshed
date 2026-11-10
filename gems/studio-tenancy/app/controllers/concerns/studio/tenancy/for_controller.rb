module Studio
  module Tenancy
    module ForController
      extend ActiveSupport::Concern

      included do
        helper_method :current_workspace, :current_organization
      end

      private

      def current_workspace
        current_user&.default_workspace
      end

      # The organization that owns the current workspace, and so pays for it.
      # For someone invited into another person's workspace, that's the host's.
      def current_organization
        current_workspace&.organization
      end
    end
  end
end
