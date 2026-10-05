# RAILS_FEATURES.md #118: a mailbox that processes inbound email.
class InboxMailbox < ApplicationMailbox
  def process
    # RAILS_FEATURES.md #118: store the inbound email for the audit trail
    # (the raw InboundEmail stays in Active Storage; we log the metadata).
    AuditLog.create!(
      action: "mailbox.inbound",
      loggable: @inbound_email
    )
  end
end
