# frozen_string_literal: true

# RAILS_FEATURES.md row 71: optimistic locking. Rails enables it
# automatically for any model with a lock_version column.
class AddLockVersionToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :lock_version, :integer, default: 0, null: false
  end
end
