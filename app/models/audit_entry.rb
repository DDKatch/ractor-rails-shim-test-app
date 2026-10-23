# frozen_string_literal: true

# RAILS_FEATURES.md #81: lives on the secondary database, never on the primary.
class AuditEntry < SecondaryRecord
  validates :message, presence: true
  validates :source, presence: true
end
