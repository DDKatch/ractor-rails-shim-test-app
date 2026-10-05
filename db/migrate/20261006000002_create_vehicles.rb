class CreateVehicles < ActiveRecord::Migration[8.1]
  def change
    create_table :vehicles do |t|
      t.string :name, null: false
      t.string :type # STI discriminator (Car / Bicycle)
      t.timestamps
    end
  end
end
