module VCAP::CloudController
  module Jobs
    module Services
      class CreateInstanceDashboardClient < VCAP::CloudController::Jobs::CCJob
        def initialize(instance_guid, dashboard_client_info, audit_event_params, services_event_repository)
          @instance_guid         = instance_guid
          @dashboard_client_info = dashboard_client_info
          @audit_event_params    = audit_event_params
          @services_event_repository = services_event_repository
        end

        def perform
          logger = Steno.logger('cc-background')
          logger.info("Performing dashboard client create for instance #{@instance_guid}")

          instance = ManagedServiceInstance.find(guid: @instance_guid)

          client_manager = VCAP::Services::SSO::DashboardClientManager.new(
            instance,
            @services_event_repository)

          client_add_result = client_manager.add_client_for_instance(@dashboard_client_info)

          if client_add_result == true
            logger.info("Successfully created dashboard client for instance #{@instance_guid}")

            @services_event_repository.record_service_instance_event(*@audit_event_params.params)
            dashboard_client_success = 'created client for service instance dashboard SSO'

            instance.db.transaction do
              instance.lock!
              instance.last_operation.update({ state: 'succeeded', description: dashboard_client_success })
            end
          else
            error_message = client_manager.errors.messages.join(', ')
            logger.error("Failed creating dashboard client for instance #{@instance_guid}: #{error_message}")

            instance.db.transaction do
              instance.lock!
              instance.last_operation.update({ state: 'failed', description: error_message })
            end

            mitigator = VCAP::Services::ServiceBrokers::V2::OrphanMitigator.new
            mitigator.cleanup_failed_provision(instance.client.attrs, instance)
          end
        end

        def job_name_in_configuration
          :create_instance_dashboard_client
        end

        def max_attempts
          1
        end
      end
    end
  end
end
