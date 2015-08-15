module VCAP::CloudController
  module Jobs
    module Services
      class InstanceAsyncWatcher < VCAP::CloudController::Jobs::CCJob
        attr_accessor :handler, :end_timestamp, :poll_interval

        def initialize(instance_guid, handler, end_timestamp=nil)
          @instance_guid = instance_guid
          @handler       = handler
          @end_timestamp = end_timestamp || new_end_timestamp
          @logger = nil
          update_polling_interval
        end

        def perform
          logger = Steno.logger('cc-background')
          logger.info("Performing async watch for instance #{@instance_guid}")

          service_instance = ManagedServiceInstance.find(guid: @instance_guid)
          client           = VCAP::Services::ServiceBrokers::V2::Client.new(service_instance.client.attrs)

          response = client.fetch_service_instance_state(service_instance)

          case response[:last_operation][:state]
          when 'succeeded'
            logger.info("Async watch for instance #{@instance_guid} succeeded")

            handler.run(response)

          when 'failed'
            logger.info("Async watch for instance #{@instance_guid} failed")

            service_instance.save_and_update_operation(
              last_operation: response[:last_operation].slice(:state, :description))

          when 'in progress'
            logger.info("Async watch for instance #{@instance_guid} is in progress")

            service_instance.save_and_update_operation(
              last_operation: response[:last_operation].slice(:state, :description))

            requeue_job(service_instance)
          end

        rescue HttpRequestError, HttpResponseError, Sequel::Error => e
          logger.error("Error performing async watch for #{@instance_guid}: #{e}")

          requeue_job(service_instance)
        end

        def job_name_in_configuration
          :instance_async_watcher
        end

        def max_attempts
          1
        end

        private

        def new_end_timestamp
          Time.now + VCAP::CloudController::Config.config[:broker_client_max_async_poll_duration_minutes].minutes
        end

        def update_polling_interval
          default_poll_interval = VCAP::CloudController::Config.config[:broker_client_default_async_poll_interval_seconds]
          poll_interval         = [default_poll_interval, 24.hours].min
          @poll_interval        = poll_interval
        end

        def requeue_job(service_instance)
          update_polling_interval

          if Time.now + @poll_interval > end_timestamp
            service_instance.save_and_update_operation(
              last_operation: {
                state:       'failed',
                description: 'Service Broker failed to perform the operation within the required time.',
              })
          else
            opts = { queue: 'cc-generic', run_at: Delayed::Job.db_time_now + @poll_interval }
            VCAP::CloudController::Jobs::Enqueuer.new(self, opts).enqueue
          end
        end
      end
    end
  end
end
