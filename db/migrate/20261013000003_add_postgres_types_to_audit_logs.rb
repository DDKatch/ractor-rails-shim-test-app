# frozen_string_literal: true

# RAILS_FEATURES.md row 82: Postgres types — jsonb metadata + a string
# array on the existing polymorphic audit_logs table.
class AddPostgresTypesToAuditLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_logs, :metadata, :jsonb, default: {}
    add_column :audit_logs, :trace_ids, :string, array: true, default: []
    add_index :audit_logs, :metadata, using: "gin"
  end
end
