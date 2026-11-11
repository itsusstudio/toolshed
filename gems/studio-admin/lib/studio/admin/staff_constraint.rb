module Studio
  module Admin
    module StaffConstraint
      class << self
        def matches?(request)
          session = ::Session.from_cookie(request.cookie_jar, scope: ::Session.includes(:user))
          write = !request.get? && !request.head?
          session.present? && session.user.staff? && session.signed_in_within?(Admin.config.sign_in_max_age(write: write))
        end
      end
    end
  end
end
