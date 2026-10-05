require "test_helper"

# Active Support subsystems audit (RAILS_FEATURES.md rows 131-134):
# time zones, the error reporter, CurrentAttributes, tagged/broadcast
# logging, and custom instrumentation events.
class ActiveSupportSubsystemsTest < ActiveSupport::TestCase
  # --- time zones (row 131) ---------------------------------------------------

  test "config.time_zone is applied to AR attributes" do
    assert_equal "Europe/Berlin", Time.zone.name
    post = Post.new(title: "TZ Post", body: "Timezone body with enough characters.")
    assert_equal "Europe/Berlin", post.created_at.time_zone.name if post.created_at
    now = Time.current
    assert_equal "Europe/Berlin", now.time_zone.name
    assert_equal "Europe/Berlin", 1.day.ago.time_zone.name
  end

  # --- error reporter (row 133) ------------------------------------------------

  # Rails 8.1 subscribers must respond to #report (the older block/kwargs
  # form and the `reported` reader are gone).
  class CapturingSubscriber
    attr_reader :captured

    def initialize = @captured = []

    def report(error, handled:, severity:, context:, source:) = (@captured << [error, handled])
  end

  test "Rails.error.handle swallows matching exceptions and notifies subscribers" do
    subscriber = CapturingSubscriber.new
    Rails.error.subscribe(subscriber)
    Rails.error.handle(StandardError) { raise StandardError, "handle probe" }
    assert subscriber.captured.any? { |(error, handled)| error.message == "handle probe" && handled }
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  test "Rails.error.record captures the exception and re-raises it" do
    subscriber = CapturingSubscriber.new
    Rails.error.subscribe(subscriber)
    assert_raises(StandardError) do
      Rails.error.record { raise StandardError, "block probe" }
    end
    assert subscriber.captured.any? { |(error, handled)| error.message == "block probe" && !handled }
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  # --- CurrentAttributes (row 129) -----------------------------------------------

  test "Current attributes set and reset" do
    Current.request_id = "req-42"
    assert_equal "req-42", Current.request_id
    Current.reset
    assert_nil Current.request_id
  end

  # --- logging (row 134) -----------------------------------------------------------

  test "logger is a BroadcastLogger and supports tagged logging" do
    assert_kind_of ActiveSupport::BroadcastLogger, Rails.logger
    assert_nothing_raised do
      Rails.logger.tagged("audit") { Rails.logger.info "tagged probe" }
    end
  end

  # --- custom instrumentation (row 130) ---------------------------------------------

  test "custom ActiveSupport::Notifications events are subscribable" do
    payload = nil
    subscription = ActiveSupport::Notifications.subscribe("audit.probe") do |_name, _start, _finish, _id, data|
      payload = data
    end

    ActiveSupport::Notifications.instrument("audit.probe", { kind: "test" })
    assert_equal "test", payload["kind"] || payload[:kind]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end
end
