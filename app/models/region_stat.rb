# RAILS_FEATURES.md row 80: composite primary key model. Every read/write
# routes its WHERE through both PK columns; `find` takes the PK tuple as
# an array. No synthetic id column exists.
class RegionStat < ApplicationRecord
  self.primary_key = [ :region, :year ]

  validates :region, :year, presence: true
end
