class AddUserIdToPosts < ActiveRecord::Migration[8.1]
  def change
    add_reference :posts, :user, null: true, foreign_key: true
  end
end
