Sequel.migration do
  change do
    drop_table(:apps)
  end
end
