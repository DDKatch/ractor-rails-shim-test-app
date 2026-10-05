require "test_helper"

# Mailer interceptors & observers audit (RAILS_FEATURES.md row 113).
# Registered test-locally so the global mail pipeline is unaffected.
class MailerHooksAuditTest < ActiveSupport::TestCase
  class AuditInterceptor
    def self.delivering_email(message)
      message.subject << " [audited]"
    end
  end

  class AuditObserver
    class << self
      attr_reader :last_delivered
    end

    def self.delivered_email(message)
      @last_delivered = message
    end
  end

  test "interceptor mutates the message before delivery" do
    ActionMailer::Base.register_interceptor(AuditInterceptor)
    mail = UserMailer.welcome_email(User.new(email: "hook@example.com"))
    assert_not_includes mail.subject, "[audited]", "interceptors run at DELIVERY time, not at build time"

    delivered = nil
    ActiveSupport::Notifications.instrument("deliver.action_mailer") do
      delivered = UserMailer.welcome_email(User.new(email: "hook@example.com")).deliver_now
    end
    assert_includes delivered.subject, "[audited]"
  ensure
    ActionMailer::Base.unregister_interceptor(AuditInterceptor)
  end

  test "observer sees the message after delivery" do
    ActionMailer::Base.register_observer(AuditObserver)
    UserMailer.welcome_email(User.new(email: "hook@example.com")).deliver_now
    assert_not_nil AuditObserver.last_delivered
    assert_equal "hook@example.com", AuditObserver.last_delivered.to.first
  ensure
    ActionMailer::Base.unregister_observer(AuditObserver)
  end

  test "mailer callback stamps the audit header on every message" do
    mail = UserMailer.welcome_email(User.new(email: "hooks@example.com")).deliver_now
    assert_equal "rails-features-audit", mail["X-Audit-Campaign"].value
  end
end
