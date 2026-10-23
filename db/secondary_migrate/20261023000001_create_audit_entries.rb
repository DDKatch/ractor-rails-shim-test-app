# frozen_string_literal: true

# RAILS_FEATURES.md #81: the secondary database's only table. Rails 7.1+
# resolves a database named `secondary` to db/secondary_migrate by convention.
class CreateAuditEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_entries do |t|
      t.string :message, null: false
      t.string :source, null: false
      t.timestamps
    end
  end
end
