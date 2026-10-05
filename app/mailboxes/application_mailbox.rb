# RAILS_FEATURES.md #117-119: Action Mailbox routing — a catch-all inbox
# mailbox that records every inbound email as an AuditLog (row 66 reuse).
class ApplicationMailbox < ActionMailbox::Base
  # RAILS_FEATURES.md #117: routing based on the TO address pattern.
  routing :all => :inbox
end
