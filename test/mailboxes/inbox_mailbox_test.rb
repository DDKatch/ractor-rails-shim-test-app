require "test_helper"

# RAILS_FEATURES.md #117-119: Action Mailbox routing + processing.
# ApplicationMailbox routes everything to InboxMailbox (routing :all => :inbox),
# which records the inbound email as an AuditLog row (polymorphic #66 reuse).
class InboxMailboxTest < ActionMailbox::TestCase
  test "routes an inbound email to InboxMailbox and records an AuditLog" do
    assert_difference -> { AuditLog.where(action: "mailbox.inbound").count }, 1 do
      receive_inbound_email_from_mail do |mail|
        mail.to = "app@example.com"
        mail.from = "sender@example.com"
        mail.subject = "Hello via Action Mailbox"
        mail.body = "Routing probe body"
      end
    end

    log = AuditLog.where(action: "mailbox.inbound").order(:created_at).last
    assert_equal "ActionMailbox::InboundEmail", log.loggable_type
    assert_kind_of ActionMailbox::InboundEmail, log.loggable

    # #119: the routed+processed inbound email is marked delivered.
    inbound = log.loggable
    assert inbound.reload.delivered?
  end

  test "routing selects the inbox mailbox for any address" do
    inbound = create_inbound_email_from_mail(to: "anything@example.com")
    assert_equal InboxMailbox, ApplicationMailbox.router.mailbox_for(inbound)
  end
end
