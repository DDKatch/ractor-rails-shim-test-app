# RAILS_FEATURES.md #67: single-table inheritance parent.
class Vehicle < ApplicationRecord
  validates :name, presence: true
end
