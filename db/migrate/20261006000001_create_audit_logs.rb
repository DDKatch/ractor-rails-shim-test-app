class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.string :action, null: false
      t.references :loggable, polymorphic: true, index: true
      t.timestamps
    end
  end
end
