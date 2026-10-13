# frozen_string_literal: true

# RAILS_FEATURES.md row 80: composite primary keys — a table whose PK is
# [region, year] instead of a synthetic id. Rails 7.1+ composite primary
# keys: CREATE TABLE ... PRIMARY KEY (region, year); the model declares
# `self.primary_key = [:region, :year]` and every find/update routes its
# WHERE through both PK columns.
class CreateRegionStats < ActiveRecord::Migration[8.1]
  def change
    # NB: no `id: false` here — with a composite `primary_key:` array,
    # Rails creates no synthetic id column anyway; passing both silently
    # dropped the PK.
    create_table :region_stats, primary_key: [:region, :year] do |t|
      t.string :region, null: false
      t.integer :year, null: false
      t.bigint :visits, default: 0, null: false
      t.timestamps
    end
  end
end
