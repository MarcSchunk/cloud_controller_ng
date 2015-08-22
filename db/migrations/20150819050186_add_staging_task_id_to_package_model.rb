Sequel.migration do
  change do
    alter_table :packages do
      add_column :staging_task_id, String
      add_index :staging_task_id
    end
  end
end
