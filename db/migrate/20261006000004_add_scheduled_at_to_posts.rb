class AddScheduledAtToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :scheduled_at, :datetime
  end
end
