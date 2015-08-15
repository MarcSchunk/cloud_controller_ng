module VCAP::Services::SSO
  class DashboardClientManager
    attr_reader :errors, :warnings

    INSTANCE_SSO_DISABLED = [
      'Warning: The broker requested a dashboard client.',
      'Auto-creation of OAuth2 clients has been disabled in this Cloud Foundry instance.',
      'The service instance has been updated but its dashboard client configuration will be ignored.'
    ].join(' ').freeze

    REQUESTED_FEATURE_DISABLED_WARNING = [
      'Warning: This broker includes configuration for a dashboard client.',
      'Auto-creation of OAuth2 clients has been disabled in this Cloud Foundry instance.',
      'The broker catalog has been updated but its dashboard client configuration will be ignored.'
    ].join(' ').freeze

    def initialize(broker_or_instance, services_event_repository)
      @dashboard_owner = DashboardOwner.new(broker_or_instance)
      @errors         = VCAP::Services::ValidationErrors.new
      @warnings       = []

      @client_manager = VCAP::Services::SSO::UAA::UaaClientManager.new

      @differ = DashboardClientDiffer.new(broker_or_instance)

      @services_event_repository = services_event_repository
    end

    def add_client_for_instance(client_info)
      if !cc_configured_to_modify_uaa_clients?
        warnings << INSTANCE_SSO_DISABLED
        return false
      end

      dashboard_owner.is_instance = true

      if !client_claimable?(VCAP::CloudController::ServiceDashboardClient.find_client_by_uaa_id(client_info['id']))
        errors.add('Service dashboard client id must be unique')
        return false
      end

      existing_clients = fetch_clients_from_uaa([client_info['id']])
      if existing_clients.any?
        errors.add('Service dashboard client id must be unique')
        return false
      end

      claim_clients_and_update_uaa([client_info], [], [])

      true
    end

    def synchronize_clients_with_catalog(catalog)
      requested_clients = catalog.services.map(&:dashboard_client).compact
      requested_client_ids = requested_clients.map { |client| client['id'] }

      unless cc_configured_to_modify_uaa_clients?
        warnings << REQUESTED_FEATURE_DISABLED_WARNING unless requested_clients.empty?
        return true
      end

      return false unless all_clients_can_be_claimed_in_db?(catalog)

      existing_ccdb_clients    = VCAP::CloudController::ServiceDashboardClient.find_clients_claimed_by(dashboard_owner)
      existing_ccdb_client_ids = existing_ccdb_clients.map(&:uaa_id)

      existing_uaa_client_ids  = fetch_clients_from_uaa(requested_client_ids | existing_ccdb_client_ids).map { |c| c['client_id'] }
      return false unless all_clients_can_be_claimed_in_uaa?(existing_uaa_client_ids, catalog)

      claim_clients_and_update_uaa(requested_clients, existing_ccdb_clients, existing_uaa_client_ids)
      true
    end

    def remove_clients_for_broker
      return unless cc_configured_to_modify_uaa_clients?

      requested_clients       = []
      existing_db_clients     = VCAP::CloudController::ServiceDashboardClient.find_clients_claimed_by(dashboard_owner)
      existing_db_client_ids  = existing_db_clients.map(&:uaa_id)
      existing_uaa_client_ids = fetch_clients_from_uaa(existing_db_client_ids).map { |client| client['client_id'] }

      claim_clients_and_update_uaa(requested_clients, existing_db_clients, existing_uaa_client_ids)
    end

    def has_warnings?
      !warnings.empty?
    end

    def self.cc_configured_to_modify_uaa_clients?
      uaa_client = VCAP::CloudController::Config.config[:uaa_client_name]
      uaa_client_secret = VCAP::CloudController::Config.config[:uaa_client_secret]
      uaa_client && uaa_client_secret
    end

    private

    attr_reader :client_manager, :differ, :dashboard_owner

    def all_clients_can_be_claimed_in_db?(catalog)
      requested_clients = catalog.services.map(&:dashboard_client).compact

      unclaimable_ids = []
      requested_clients.each do |client|
        existing_client_in_ccdb = VCAP::CloudController::ServiceDashboardClient.find_client_by_uaa_id(client['id'])
        unclaimable_ids << existing_client_in_ccdb.uaa_id unless client_claimable?(existing_client_in_ccdb)
      end

      if !unclaimable_ids.empty?
        populate_uniqueness_errors(catalog, unclaimable_ids)
        return false
      end
      true
    end

    def all_clients_can_be_claimed_in_uaa?(existing_uaa_client_ids, catalog)
      unclaimable_ids = []
      existing_uaa_client_ids.each do |id|
        existing_client_in_ccdb = VCAP::CloudController::ServiceDashboardClient.find_client_by_uaa_id(id)
        unclaimable_ids << id if existing_client_in_ccdb.nil?
      end

      if !unclaimable_ids.empty?
        populate_uniqueness_errors(catalog, unclaimable_ids)
        return false
      end
      true
    end

    def fetch_clients_from_uaa(requested_client_ids)
      client_manager.get_clients(requested_client_ids)
    rescue VCAP::CloudController::UaaError => e
      raise VCAP::Errors::ApiError.new_from_details('ServiceBrokerDashboardClientFailure', e.message)
    end

    def client_claimable?(existing_client_in_ccdb)
      existing_client_in_ccdb.nil? ||
        existing_client_in_ccdb.unclaimed? ||
        existing_client_in_ccdb.claimed_by?(dashboard_owner)
    end

    def claim_clients_and_update_uaa(requested_clients, existing_db_clients, existing_uaa_clients)
      db_changeset  = differ.create_db_changeset(requested_clients, existing_db_clients)
      uaa_changeset = differ.create_uaa_changeset(requested_clients, existing_uaa_clients)

      begin
        dashboard_owner.db.transaction do
          db_changeset.each(&:db_command)
          client_manager.modify_transaction(uaa_changeset)
        end
      rescue VCAP::CloudController::UaaError => e
        raise VCAP::Errors::ApiError.new_from_details('ServiceBrokerDashboardClientFailure', e.message)
      end

      uaa_changeset.each do |uaa_cmd|
        case uaa_cmd.uaa_command[:action]
        when 'add'
          @services_event_repository.record_service_dashboard_client_event(
           :create, uaa_cmd.client_attrs, dashboard_owner)
        when 'delete'
          @services_event_repository.record_service_dashboard_client_event(
            :delete, uaa_cmd.client_attrs, dashboard_owner)
        end
      end
    end

    def populate_uniqueness_errors(catalog, non_unique_ids)
      catalog.services.each do |service|
        if service.dashboard_client && non_unique_ids.include?(service.dashboard_client['id'])
          errors.add_nested(service).add('Service dashboard client id must be unique')
        end
      end
    end

    def cc_configured_to_modify_uaa_clients?
      DashboardClientManager.cc_configured_to_modify_uaa_clients?
    end
  end
end
