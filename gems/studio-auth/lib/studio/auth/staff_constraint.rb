module Studio
  module Auth
    # For engines mounted in routes (job dashboards, feature flag UIs), which
    # never pass through ForStaffController. A request it refuses falls
    # through to the next route, so a catch-all admin route behind
    # ForStaffController can answer it.
    module StaffConstraint
      class << self
        def matches?(request)
          session = ::Session.from_cookie(request.cookie_jar, scope: ::Session.includes(:user))
          write = !request.get? && !request.head?
          session.present? && session.user.staff? && session.recent_enough_for_staff?(write: write)
        end
      end
    end
  end
end
