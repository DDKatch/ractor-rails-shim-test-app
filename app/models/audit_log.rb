# RAILS_FEATURES.md #66: polymorphic association — AuditLog can hang off
# any model (Post, User, ...).
class AuditLog < ApplicationRecord
  belongs_to :loggable, polymorphic: true, optional: true

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
