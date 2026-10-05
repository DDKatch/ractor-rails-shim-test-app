class AddStateToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :state, :integer, default: 0, null: false
    add_index :posts, :state
  end
end
