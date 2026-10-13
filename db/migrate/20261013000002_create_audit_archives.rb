# frozen_string_literal: true

# RAILS_FEATURES.md row 83: advanced migrations — one migration exercising
# reversible() + a foreign key + a check constraint. Fully reversible via
# `change`: create_table/add_foreign_key/add_check_constraint all invert
# automatically; the COMMENT uses an explicit reversible() block because
# comments need direction-specific SQL.
class CreateAuditArchives < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_archives do |t|
      t.string :label, null: false
      t.bigint :post_id
      t.jsonb :payload, default: {}
      t.timestamps
    end

    add_index :audit_archives, :post_id
    add_foreign_key :audit_archives, :posts
    add_check_constraint :audit_archives, "length(label) > 0",
                         name: "audit_archives_label_check"

    reversible do |dir|
      dir.up do
        execute <<~SQL
          COMMENT ON TABLE audit_archives IS 'RAILS_FEATURES row 83: reversible + FK + check constraint'
        SQL
      end
      dir.down do
        execute <<~SQL
          COMMENT ON TABLE audit_archives IS NULL
        SQL
      end
    end
  end
end
