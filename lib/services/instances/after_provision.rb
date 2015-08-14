require 'jobs/services/create_instance_dashboard_client'

module VCAP::CloudController
  module Services::Instances
    class AfterProvision
      def initialize(service_instance, audit_event_params, dashboard_client_info)
        @service_instance = service_instance
        @audit_event_params = audit_event_params
        @dashboard_client_info = dashboard_client_info
      end
      
      def run(response)
        if @dashboard_client_info
          setup_dashboard
        else
          @service_instance.save_and_update_operation(
            last_operation: response[:last_operation].slice(:state, :description))

          services_event_repository.record_service_instance_event(*@audit_event_params.params)
        end
      end

      def setup_dashboard
        # if !broker_response[:instance].key?(:dashboard_url) || broker_response[:instance][:dashboard_url].nil?
        #   log_message = 'Missing dashboard_url from broker response while creating a service instance with dashboard_client'
        #   e = VCAP::Errors::ApiError.new_from_details('ServiceDashboardClientMissingUrl', log_message)
        #   mitigate_orphan(e, service_instance, message: log_message)
        # end

        job = Jobs::Services::CreateInstanceDashboardClient.new
        enqueuer = Jobs::Enqueuer.new(job, queue: 'cc-generic')

        begin
          @service_instance.db.transaction do
            @service_instance.lock!

            @service_instance.last_operation.update({ type: :create, state: 'in progress', description: 'creating dashboard client' })
            enqueuer.enqueue
          end
        rescue => e
          logger.error "Failed to save while creating service instance #{@service_instance.guid} with exception: #{e}."
          orphan_mitigator = SynchronousOrphanMitigate.new(logger)
          orphan_mitigator.attempt_deprovision_instance(@service_instance)
          raise e
        end

        # client_manager = VCAP::Services::SSO::DashboardClientManager.new(
        #   service_instance,
        #   @services_event_repository)
        #
        # client_add_result = client_manager.add_client_for_instance(dashboard_client_info)
        #
        # if client_add_result == false
        #   log_message = 'Unable to add service instance dashboard client to UAA'
        #   e = VCAP::Errors::ApiError.new_from_details('ServiceInstanceDashboardClientFailure', client_manager.errors.messages.join(', '))
        #   mitigate_orphan(e, service_instance, message: log_message)
        # end
      end

      def services_event_repository
        CloudController::DependencyLocator.instance.services_event_repository
      end

      def logger
        @logger ||= Steno.logger('cc.services.instances.after_provision')
      end
    end
  end
end
