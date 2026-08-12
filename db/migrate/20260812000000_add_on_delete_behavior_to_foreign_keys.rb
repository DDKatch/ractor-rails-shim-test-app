# Back the `dependent:` associations with DB-level ON DELETE behavior so that
# deleting a parent works correctly under Ractor mode. In worker Ractors the
# Rails callback chain for `dependent: :destroy` / `dependent: :nullify` is
# intentionally empty (the __callbacks class_attribute cannot be made
# Ractor-shareable — it holds a Mutex + per-callback lambdas), so the Ruby
# path never runs there. Without a DB constraint the parent DELETE then hits a
# foreign-key violation. ON DELETE CASCADE / NULLIFY performs the same work at
# the SQL layer, which is Ractor-safe. Main (non-Ractor) behavior is unchanged:
# the Ruby `dependent:` callbacks still run and the constraint is a no-op backup.
class AddOnDeleteBehaviorToForeignKeys < ActiveRecord::Migration[8.1]
  def change
    # Post has_many :comments, dependent: :destroy
    remove_foreign_key :comments, :posts
    add_foreign_key :comments, :posts, on_delete: :cascade

    # User has_many :posts, dependent: :destroy
    remove_foreign_key :posts, :users
    add_foreign_key :posts, :users, on_delete: :cascade

    # User has_many :comments, dependent: :destroy
    remove_foreign_key :comments, :users
    add_foreign_key :comments, :users, on_delete: :cascade

    # Category has_many :posts, dependent: :nullify
    remove_foreign_key :posts, :categories
    add_foreign_key :posts, :categories, on_delete: :nullify
  end
end
