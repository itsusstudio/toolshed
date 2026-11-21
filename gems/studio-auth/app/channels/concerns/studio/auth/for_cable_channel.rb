module Studio
  module Auth
    module ForCableChannel
      extend ActiveSupport::Concern

      SESSION_RECHECK = 5.minutes

      included do
        delegate :current_session, to: :connection
        before_subscribe :require_authorization
        periodically :recheck_access, every: SESSION_RECHECK
      end

      def current_user
        current_session&.user
      end

      private

      def authorized?
        raise NotImplementedError, "#{self.class.name} must define authorized? to say who may subscribe"
      end

      # For a Turbo::StreamsChannel: the records and names its signed stream was built from.
      def streamables
        name = try(:verified_stream_name_from_params)
        return [] if name.blank?

        name.split(":").map { |part| GlobalID::Locator.locate(part) || part }
      end

      def require_authorization
        return if authorized?

        reject
        throw :abort
      rescue NotImplementedError
        reject_subscription
        raise
      rescue ActiveRecord::RecordNotFound
        reject
        throw :abort
      end

      # Access is checked when a socket opens and when it subscribes, so without this a socket left open would
      # outlive a sign-out elsewhere, an expired session, an archived user or a removal from the team.
      def recheck_access
        if !current_session.class.active.exists?(current_session.id) || !current_session.reload.user.can_sign_in?
          return close_connection(reconnect: false)
        end

        # Reconnecting resubscribes every stream on the socket, so only the ones still allowed come back.
        close_connection(reconnect: true) if !authorized?
      rescue ActiveRecord::RecordNotFound
        close_connection(reconnect: true)
      end

      def close_connection(reconnect:)
        connection.close(reason: ActionCable::INTERNAL[:disconnect_reasons][:unauthorized], reconnect: reconnect)
      end
    end
  end
end
