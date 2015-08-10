Sequel.migration do
  up do
    drop_table(:service_instance_dashboard_clients)

    alter_table(:service_dashboard_clients) do
      add_column :claimant_guid, String, default: nil
      add_index :claimant_guid
    end

    run <<-SQL
      UPDATE service_dashboard_clients
        SET claimant_guid = (
          SELECT service_brokers.guid
            FROM service_brokers
            WHERE service_brokers.id = service_dashboard_clients.service_broker_id
          )
    SQL

    alter_table(:service_dashboard_clients) do
      drop_column :service_broker_id
    end
  end

  down do
    create_table :service_instance_dashboard_clients do
      primary_key :id

      VCAP::Migration.timestamps(self, 's_i_d_clients')

      String :uaa_id, null: false
      Integer :managed_service_instance_id

      index :uaa_id, unique: true, name: 's_i_d_clients_uaa_id_unique'
      index :managed_service_instance_id, name: 'svc_inst_dash_cli_svc_inst_id_idx'
    end

    alter_table(:service_dashboard_clients) do
      add_column :service_broker_id, Integer, default: nil
      add_index :service_broker_id, name: :svc_dash_cli_svc_brkr_id_idx
    end

    run <<-SQL
      UPDATE service_dashboard_clients
        SET service_broker_id = (
          SELECT service_brokers.id
            FROM service_brokers
            WHERE service_brokers.guid = service_dashboard_clients.claimant_guid
          )
    SQL

    alter_table(:service_dashboard_clients) do
      drop_column :claimant_guid
    end
  end
end
