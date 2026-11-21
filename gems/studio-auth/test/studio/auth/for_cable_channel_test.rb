require "test_helper"

class CheckedChannel < ActionCable::Channel::Base
  include Studio::Auth::ForCableChannel

  def subscribed
    stream_from "checked"
  end

  private

  def authorized?
    params[:room] == "open"
  end
end

class UncheckedChannel < ActionCable::Channel::Base
  include Studio::Auth::ForCableChannel

  def subscribed
    stream_from "unchecked"
  end
end

class StreamsChannel < Turbo::StreamsChannel
  include Studio::Auth::ForCableChannel

  private

  def authorized?
    streamables.all? { !it.is_a?(User) || it == current_user }
  end
end

class Studio::Auth::ForCableChannelTest < ActionCable::Channel::TestCase
  tests CheckedChannel

  setup do
    @user = User.create!(email_address: "cook@studio.com")
    @session = @user.sessions.create!
    stub_connection current_session: @session
  end

  test "#subscribe lets in whoever the channel authorizes" do
    subscribe room: "open"

    assert_predicate subscription, :confirmed?
    assert_has_stream "checked"
  end

  test "#subscribe refuses whoever the channel doesn't authorize" do
    subscribe room: "closed"

    assert_predicate subscription, :rejected?
    assert_no_streams
  end

  test "#subscribe refuses and raises in a channel that never says who may subscribe" do
    @subscription = UncheckedChannel.new(connection, "{}", {})

    assert_raises(NotImplementedError) { @subscription.subscribe_to_channel }
    assert_equal "reject_subscription", connection.transmissions.last["type"]
    assert_empty @subscription.send(:streams)
  end

  test "#current_user is the session's user" do
    subscribe room: "open"

    assert_equal @user, subscription.current_user
  end

  test "the socket stays open while its session is live" do
    subscribe room: "open"
    connection.expects(:close).never

    subscription.send(:recheck_access)
  end

  test "the socket closes once its session ends" do
    subscribe room: "open"
    @session.destroy!
    connection.expects(:close).with(reason: "unauthorized", reconnect: false)

    subscription.send(:recheck_access)
  end

  test "the socket reconnects without a stream its user may no longer watch" do
    subscribe room: "open"
    subscription.stubs(:authorized?).returns(false)
    connection.expects(:close).with(reason: "unauthorized", reconnect: true)

    subscription.send(:recheck_access)
  end

  test "the socket closes once its user can no longer sign in" do
    subscribe room: "open"
    User.any_instance.stubs(:can_sign_in?).returns(false)
    connection.expects(:close).with(reason: "unauthorized", reconnect: false)

    subscription.send(:recheck_access)
  end
end

class Studio::Auth::CableDisconnectTest < ActiveSupport::TestCase
  test ".disconnect drops every socket of the given sessions for good" do
    user = User.create!(email_address: "cook@studio.com")
    sessions = [user.sessions.create!, user.sessions.create!]
    remote = mock
    remote.expects(:disconnect).with(reconnect: false).twice
    sessions.each { ActionCable.server.remote_connections.expects(:where).with(current_session: it).returns(remote) }

    Studio::Auth::Cable.disconnect(sessions)
  end
end

class Studio::Auth::UncheckedChannelsTest < ActiveSupport::TestCase
  test ".unchecked_channels names channels with no authorized? of their own" do
    assert_equal ["UncheckedChannel"], Studio::Auth::Cable.unchecked_channels(__dir__)
  end
end

class Studio::Auth::StreamsChannelTest < ActionCable::Channel::TestCase
  tests StreamsChannel

  setup do
    @user = User.create!(email_address: "cook@studio.com")
    stub_connection current_session: @user.sessions.create!
  end

  test "#subscribe lets a user watch a stream of their own record" do
    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([@user, :jobs])

    assert_predicate subscription, :confirmed?
    assert_has_stream Turbo::StreamsChannel.send(:stream_name_from, [@user, :jobs])
  end

  test "#subscribe refuses a stream of someone else's record, even with a valid signature" do
    other = User.create!(email_address: "other@studio.com")

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([other, :jobs])

    assert_predicate subscription, :rejected?
  end

  test "#subscribe refuses a stream of a deleted record" do
    other = User.create!(email_address: "gone@studio.com")
    name = Turbo::StreamsChannel.signed_stream_name([other, :jobs])
    other.destroy!

    subscribe signed_stream_name: name

    assert_predicate subscription, :rejected?
  end
end

class Studio::Auth::TurboStreamsChannelTest < ActionCable::Channel::TestCase
  tests Turbo::StreamsChannel

  test "Turbo's own channel refuses every subscription, signed or not" do
    user = User.create!(email_address: "cook@studio.com")
    stub_connection current_session: user.sessions.create!

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([user, :jobs])

    assert_predicate subscription, :rejected?
  end
end

class Studio::Auth::DefaultStreamsChannelTest < ActionView::TestCase
  helper Turbo::StreamsHelper

  test "#turbo_stream_from subscribes through the app's StreamsChannel unless told otherwise" do
    assert_includes turbo_stream_from("room"), 'channel="StreamsChannel"'
    assert_includes turbo_stream_from("room", channel: "RoomChannel"), 'channel="RoomChannel"'
  end
end
