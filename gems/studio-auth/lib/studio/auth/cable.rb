module Studio
  module Auth
    # turbo_stream_from defaults to Turbo::StreamsChannel, which trusts any signed stream name forever.
    # Streams go through the app's StreamsChannel instead, which says who may watch each one.
    module Cable
      DEFAULT_CHANNEL = "StreamsChannel"

      module DefaultStreamsChannel
        def turbo_stream_from(*streamables, **attributes)
          attributes[:channel] ||= DEFAULT_CHANNEL
          super
        end
      end

      module RefuseUncheckedStreams
        def subscribed
          return super if self.class != ::Turbo::StreamsChannel

          logger.warn "studio-auth: refused a subscription to Turbo::StreamsChannel; streams go through #{DEFAULT_CHANNEL}"
          reject
        end
      end

      class << self
        # Drops the sockets of sessions that just ended, like when someone leaves a team, instead of at the next
        # recheck. Collect the sessions before ending them: once they're gone there's nothing left to find them by.
        def disconnect(sessions)
          return if !defined?(::ActionCable)

          sessions.each { ::ActionCable.server.remote_connections.where(current_session: it).disconnect(reconnect: false) }
        end

        # The channels defined under path that let anyone subscribe: no ForCableChannel, or no authorized? of their own.
        def unchecked_channels(path)
          ActionCable::Channel::Base.descendants.filter_map do |channel|
            next if channel.name.nil? || channel.name == "ApplicationCable::Channel"
            next if !Object.const_source_location(channel.name)&.first.to_s.start_with?(path.to_s)
            next if channel < ForCableChannel && channel.instance_method(:authorized?).owner != ForCableChannel

            channel.name
          end
        end

        def install
          # Turbo's channel inherits from Action Cable, so naming it in an app without Action Cable fails to load.
          return if !defined?(::ActionCable::Channel::Base) || !defined?(::Turbo::StreamsChannel)

          ::Turbo::StreamsHelper.prepend(DefaultStreamsChannel) if !(::Turbo::StreamsHelper < DefaultStreamsChannel)
          ::Turbo::StreamsChannel.prepend(RefuseUncheckedStreams) if !(::Turbo::StreamsChannel < RefuseUncheckedStreams)
        end
      end
    end
  end
end
