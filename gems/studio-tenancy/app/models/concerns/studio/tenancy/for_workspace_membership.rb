module Studio
  module Tenancy
    module ForWorkspaceMembership
      extend ActiveSupport::Concern

      included do
        enum :role, MEMBERSHIP_ROLES.index_by(&:itself)

        belongs_to :user
        belongs_to :workspace

        validates :role, presence: true, inclusion: {in: MEMBERSHIP_ROLES}
        validates :user_id, uniqueness: {scope: :workspace_id}
        validates :user_id, uniqueness: {conditions: -> { where(is_default: true) }}, if: :is_default?
      end
    end
  end
end
