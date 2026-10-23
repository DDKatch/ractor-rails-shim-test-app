# frozen_string_literal: true

require "test_helper"

# RAILS_FEATURES.md #122: connection identifiers + rejected connections.
#
# These semantics live on the cable server's connection object, which kino's
# :ractor mode never creates (it serves HTTP only). The test therefore runs
# in the main Ractor, against the real ApplicationCable::Connection — the same
# class the (main-Ractor) cable server instantiates per websocket.
class ApplicationCableConnectionTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection

  test "sets current_user from the encrypted session cookie" do
    user = users(:one)
    cookies.encrypted[:user_id] = user.id

    connect

    assert_equal user, connection.current_user
  end

  test "rejects the connection without a verified user cookie" do
    assert_reject_connection { connect }
  end
end
