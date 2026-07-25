class AddUniqueIndexToProjectNames < ActiveRecord::Migration[8.1]
  def up
    rename_duplicate_project_names
    add_index :projects, :name, unique: true
  end

  def down
    remove_index :projects, :name
  end

  private

  def rename_duplicate_project_names
    duplicate_names = select_values("SELECT name FROM projects GROUP BY name HAVING COUNT(*) > 1")

    duplicate_names.each do |name|
      project_ids = select_values("SELECT id FROM projects WHERE name = #{quote(name)} ORDER BY id")

      project_ids.drop(1).each do |id|
        execute "UPDATE projects SET name = #{quote(unique_duplicate_name(name, id))} WHERE id = #{id.to_i}"
      end
    end
  end

  def unique_duplicate_name(name, id)
    candidate = "#{name} (#{id})"
    suffix = 2

    while select_value("SELECT 1 FROM projects WHERE name = #{quote(candidate)} AND id != #{id.to_i} LIMIT 1")
      candidate = "#{name} (#{id}-#{suffix})"
      suffix += 1
    end

    candidate
  end
end
