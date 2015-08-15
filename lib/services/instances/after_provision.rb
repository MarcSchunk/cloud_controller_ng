require 'jobs/services/create_instance_dashboard_client'

module VCAP::CloudController
  module Services::Instances
    class AfterProvision
      def initialize(service_instance, audit_event_params, dashboard_client_info, services_event_repository)
        @service_instance      = service_instance
        @audit_event_params    = audit_event_params
        @dashboard_client_info = dashboard_client_info
        @services_event_repository = services_event_repository
      end

      def run(response)
        if @dashboard_client_info
          setup_dashboard
        else
          @service_instance.save_and_update_operation(
            last_operation: response[:last_operation].slice(:state, :description))
          @services_event_repository.record_service_instance_event(*@audit_event_params.params)
        end
      end

      def setup_dashboard
        if @service_instance.values[:dashboard_url].nil?
          log_message = 'Missing dashboard_url from broker response; dashboard_url is required when dashboard_client is provided'
          logger.error(log_message)

          @service_instance.db.transaction do
            @service_instance.lock!
            @service_instance.last_operation.update({ state: 'failed', description: log_message })
          end

          mitigator = VCAP::Services::ServiceBrokers::V2::OrphanMitigator.new
          mitigator.cleanup_failed_provision(@service_instance.client.attrs, @service_instance)
          return
        end

        job      = Jobs::Services::CreateInstanceDashboardClient.new(@service_instance.guid, @dashboard_client_info, @audit_event_params, @services_event_repository)
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
      end

      def logger
        @logger ||= Steno.logger('cc.services.instances.after_provision')
      end
    end
  end
end
