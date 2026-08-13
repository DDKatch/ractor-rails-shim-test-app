# Back the `dependent:` associations with DB-level ON DELETE behavior was the
# original fix, but the shim now transports `dependent:` cascades into worker
# Ractors via SHAREABLE_DEPENDENT_ASSOCIATIONS (see replay_destroy_dependents!
# in storage_strategy.rb). The FK constraints below intentionally carry NO
# `on_delete:` action so this migration is a no-op-level check that the Ruby
# `dependent:` path (now replayed in workers) is what performs the cascade. If
# the transport were missing, deleting a parent here would raise a foreign-key
# violation — so a green ractor-mode delete is a real test of the shim.
class AddOnDeleteBehaviorToForeignKeys < ActiveRecord::Migration[8.1]
  def change
    # Post has_many :comments, dependent: :destroy  -> replayed in workers
    # (FK left without on_delete so the Ruby path is the sole cascade path)
    remove_foreign_key :comments, :posts
    add_foreign_key :comments, :posts

    # User has_many :posts, dependent: :destroy -> replayed in workers
    remove_foreign_key :posts, :users
    add_foreign_key :posts, :users

    # User has_many :comments, dependent: :destroy -> replayed in workers
    remove_foreign_key :comments, :users
    add_foreign_key :comments, :users

    # Category has_many :posts, dependent: :nullify -> replayed in workers
    remove_foreign_key :posts, :categories
    add_foreign_key :posts, :categories
  end
end
