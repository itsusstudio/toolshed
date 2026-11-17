module Studio
  module Auth
    module ForController
      # Starting and ending sessions, and the hooks around sign-in.
      module Sessions
        extend ActiveSupport::Concern

        private

        # reset_session drops any session id an attacker planted before sign-in.
        # The browser's previous session row ends too, so a copy of its old
        # cookie stops working.
        def start_new_session_for(user)
          current_session&.destroy
          return_to = session[RETURN_TO_KEY]
          reset_session
          session[RETURN_TO_KEY] = return_to if return_to

          new_session = user.sessions.create!(**request_details)
          new_session.write_cookie(cookies)
          assign_current_session(new_session)
          Rails.event.notify("authentication.session_started", actor_id: user.id)

          DeviceCookie.new(cookies).trust_for(user, **request_details)
          after_sign_in(user)
          new_session
        end

        def after_sign_in(user)
        end

        def after_invitation_accepted(user)
        end

        def terminate_session
          if (session = current_session)
            Rails.event.notify("authentication.session_ended") if session.destroy
            disconnect_cable([session])
          end
          forget_session
        end

        def terminate_all_sessions
          if (user = current_user)
            end_sessions(user.sessions)
            user.known_devices.delete_all
            user.login_codes.live.update_all(expires_at: Time.current)
            Rails.event.notify("authentication.all_sessions_ended", actor_id: user.id)
          end
          forget_session
        end

        def end_sessions(sessions)
          ended = sessions.to_a
          sessions.delete_all
          disconnect_cable(ended)
        end

        # An open socket outlives its cookie and would keep receiving
        # broadcasts. ForCableConnection identifies sockets by session.
        def disconnect_cable(sessions)
          return if !defined?(::ActionCable)

          sessions.each { ::ActionCable.server.remote_connections.where(current_session: it).disconnect }
        end

        def forget_session
          assign_current_session(nil)
          ::Session.delete_cookie(cookies)
          reset_session
        end

        def request_details
          {user_agent: request.user_agent, ip_address: request.remote_ip}
        end
      end
    end
  end
end
