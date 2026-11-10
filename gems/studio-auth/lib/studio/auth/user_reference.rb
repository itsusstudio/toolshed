module Studio
  module Auth
    # The gem's own models are not reloaded with the app, so a `belongs_to
    # :user` would cache the User class from before a development reload and
    # then reject the new one. Look ::User up on every call instead.
    module UserReference
      def user
        return @user if defined?(@user) && @user && @user.id == user_id

        @user = user_id && ::User.find_by(id: user_id)
      end

      def user=(value)
        @user = value
        self.user_id = value&.id
      end
    end
  end
end
