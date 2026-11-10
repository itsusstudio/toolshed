module Studio
  module Tenancy
    module ForOrganizationMembership
      extend ActiveSupport::Concern

      included do
        enum :role, MEMBERSHIP_ROLES.index_by(&:itself)

        belongs_to :user
        belongs_to :organization

        validates :role, presence: true, inclusion: {in: MEMBERSHIP_ROLES}
        validates :user_id, uniqueness: {scope: :organization_id}
      end
    end
  end
end
