require "test_helper"

# RAILS_FEATURES.md #122-124: Action Cable via Solid Cable (the Rails 8
# default database-backed pubsub). A broadcast is a DB INSERT into
# solid_cable_messages — verifiable without a WebSocket client or the
# cable server; delivery to subscribed clients is the cable server's
# poller job (a main-Ractor concern in the kino, out of :ractor scope).
# The worker-side broadcast path is probed by GET /cable_probe in the
# :ractor kino (ractor_server_test.rb).
class SolidCableAuditTest < ActiveSupport::TestCase
  setup do
    SolidCable::Message.delete_all
  end

  test "broadcast lands in solid_cable_messages as a DB row" do
    ActionCable.server.broadcast("solid_cable_audit", { "ractor" => false, "msg" => "main broadcast" })

    # Broadcasts flush asynchronously (writer_batch_delay: 1ms + margin).
    row = nil
    20.times do
      row = SolidCable::Message.order(:created_at).last
      break if row
      sleep 0.05
    end

    assert row, "broadcast must be persisted as a solid_cable_messages row"
    assert_equal "solid_cable_audit", row.channel
    assert_equal "main broadcast", JSON.parse(row.payload)["msg"]
  end
end
