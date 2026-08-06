class Category < ApplicationRecord
  has_many :posts, dependent: :nullify

  validates :name, presence: true, uniqueness: true, length: { maximum: 100 }

  before_validation :normalize_name

  scope :alphabetical, -> { order(name: :asc) }
  scope :with_counts, -> { left_joins(:posts).select("categories.*, COUNT(posts.id) AS posts_count").group(:id) }

  private

  def normalize_name
    self.name = name.to_s.strip.titleize
  end
end
