module Studio
  module Tenancy
    module ForOrganization
      extend ActiveSupport::Concern

      included do
        has_many :organization_memberships, dependent: :destroy
        # has_one :through can't go through a has_many, so this singles out
        # the owner's membership first.
        has_one :owner_membership, -> { owner }, class_name: "OrganizationMembership"
        has_one :owner, through: :owner_membership, source: :user
        has_many :workspaces, dependent: :destroy

        validates :name, presence: true
      end
    end
  end
end
