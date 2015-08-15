require 'actions/services/synchronous_orphan_mitigate'
require 'jobs/services/instance_async_watcher'

module VCAP::CloudController
  class InvalidDashboardInfo < StandardError
  end
  class ServiceInstanceCreate
    def initialize(logger, warning_observer, services_event_repository)
      @logger           = logger
      @warning_observer = warning_observer
      @services_event_repository = services_event_repository
    end

    def create(request_attrs, accepts_incomplete)
      request_params   = request_attrs.except('parameters')
      arbitrary_params = request_attrs['parameters']

      service_instance = ManagedServiceInstance.new(request_params)
      seed_operation   = { type: :create, state: 'in progress' }

      broker_response = service_instance.client.provision(
        service_instance,
        accepts_incomplete:   accepts_incomplete,
        arbitrary_parameters: arbitrary_params
      )

      begin
        service_instance.save_with_new_operation(broker_response[:instance], seed_operation)
      rescue => e
        mitigate_orphan(e, service_instance)
      end

      dashboard_client_info = broker_response[:dashboard_client]
      if dashboard_client_info && !VCAP::Services::SSO::DashboardClientManager.cc_configured_to_modify_uaa_clients?
        @warning_observer.add_warning(VCAP::Services::SSO::DashboardClientManager::INSTANCE_SSO_DISABLED)
        dashboard_client_info = nil
      end

      audit_event_params = VCAP::CloudController::Services::Instances::CreateEventParams.new(service_instance, request_attrs)
      after_provision    = VCAP::CloudController::Services::Instances::AfterProvision.new(service_instance, audit_event_params, dashboard_client_info,  @services_event_repository)

      if broker_response[:last_operation][:state] == 'in progress'
        setup_async_job(service_instance, after_provision)
      else
        after_provision.run(broker_response)
      end

      service_instance
    end

    def setup_async_job(instance, after_provision)
      job      = VCAP::CloudController::Jobs::Services::InstanceAsyncWatcher.new(instance.guid, after_provision)
      enqueuer = Jobs::Enqueuer.new(job, queue: 'cc-generic')
      enqueuer.enqueue
    end

    def mitigate_orphan(e, service_instance, message: 'Failed to save while creating service instance')
      @logger.error "#{message} #{service_instance.guid} with exception: #{e}."
      orphan_mitigator = SynchronousOrphanMitigate.new(@logger)
      orphan_mitigator.attempt_deprovision_instance(service_instance)
      raise e
    end
  end
end
