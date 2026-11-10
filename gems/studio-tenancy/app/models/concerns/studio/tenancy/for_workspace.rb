module Studio
  module Tenancy
    module ForWorkspace
      extend ActiveSupport::Concern

      included do
        belongs_to :organization
        has_many :workspace_memberships, dependent: :destroy

        validates :name, presence: true
      end
    end
  end
end
