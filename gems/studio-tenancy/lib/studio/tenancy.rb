require "rails"
require "studio/auth"

module Studio
  module Tenancy
    MEMBERSHIP_ROLES = ["owner", "admin", "member", "guest"].freeze
  end
end

require "studio/tenancy/engine"
