class AddStatusToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :status, :integer, null: false, default: 0
    add_column :projects, :disabled_at, :datetime

    add_index :projects, :status
  end
end
