class CreateTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags do |t|
      t.string :name, null: false, index: { unique: true }
      t.timestamps
    end

    create_join_table :posts, :tags do |t|
      t.index [:post_id, :tag_id]
      t.index [:tag_id, :post_id]
    end
  end
end
