# Solid Cache (RAILS_FEATURES.md TODO #26): the Rails 8 default cache
# store, pointed at the primary database for the single-DB kino
# (config/cache.yml: production database: primary). Schema taken from
# db/cache_schema.rb (solid_cache:install), wrapped as a regular migration.
class CreateSolidCacheEntries < ActiveRecord::Migration[7.2]
  def change
    create_table "solid_cache_entries", force: :cascade do |t|
      t.binary "key", limit: 1024, null: false
      t.binary "value", limit: 536870912, null: false
      t.datetime "created_at", null: false
      t.integer "key_hash", limit: 8, null: false
      t.integer "byte_size", limit: 4, null: false
      t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
      t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
      t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
    end
  end
end
