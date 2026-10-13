class AuditArchive < ApplicationRecord
  # RAILS_FEATURES.md rows 83 (advanced migrations) + 82 (Postgres types):
  # created by a migration exercising reversible + FK + check constraint;
  # payload is a jsonb column queried with containment in workers.
  belongs_to :post, optional: true

  validates :label, presence: true
end
