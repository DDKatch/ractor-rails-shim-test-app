# RAILS_FEATURES.md #68: has_and_belongs_to_many with posts (posts_tags join).
class Tag < ApplicationRecord
  has_and_belongs_to_many :posts

  validates :name, presence: true, uniqueness: true
end
