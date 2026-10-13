class Category < ApplicationRecord
  has_many :posts, dependent: :nullify

  validates :name, presence: true, uniqueness: true, length: { maximum: 100 }

  before_validation :normalize_name

  scope :alphabetical, -> { order(name: :asc) }
  scope :with_counts, -> { left_joins(:posts).select("categories.*, COUNT(posts.id) AS posts_count").group(:id) }

  # RAILS_FEATURES.md #78: default_scope / unscoped. An ORDER-based default
  # scope (safe for existing callers — no rows are hidden); `unscoped`
  # removes it, so `Category.all` and `Category.unscoped.all` can disagree
  # on order while both return the same rows.
  default_scope { order(:name) }

  private

  def normalize_name
    self.name = name.to_s.strip.titleize
  end
end
