module Studio
  module Tenancy
    module ForUser
      extend ActiveSupport::Concern

      included do
        has_many :organization_memberships, dependent: :destroy
        has_many :workspace_memberships, dependent: :destroy
        has_one :default_workspace_membership, -> { where(is_default: true) }, class_name: "WorkspaceMembership"

        after_create_commit :create_first_organization
        # Runs before organization memberships are destroyed, while it can
        # still find them.
        before_destroy :destroy_owned_organizations, prepend: true
      end

      # Without a default, the oldest workspace the user owns.
      def default_workspace
        default_workspace_membership&.workspace || workspace_memberships.owner.order(:created_at).first&.workspace
      end

      private

      def create_first_organization
        transaction do
          organization = ::Organization.create!(name: name)
          organization_memberships.create!(organization: organization, role: :owner)
          workspace = organization.workspaces.create!(name: name)
          workspace_memberships.create!(workspace: workspace, role: :owner, is_default: true)
        end
      end

      def destroy_owned_organizations
        organization_memberships.owner.includes(:organization).map(&:organization).each(&:destroy!)
      end
    end
  end
end
