module VCAP::CloudController
  module Diego
    class Stager
      def initialize(messenger, completion_handler, staging_config)
        @messenger = messenger
        @completion_handler = completion_handler
        @staging_config = staging_config
      end

      def stage_package(package, droplet, stack, memory_limit, disk_limit, buildpack_key, buildpack_url)
        if package.staging_task_id
          @messenger.send_stop_staging_request(package)
        end

        send_stage_request_for_resource(package)
      rescue Errors::ApiError => e
        logger.error('stage.package', staging_guid: StagingGuid.from(package), error: e)
        staging_complete(StagingGuid.from(package), { error: { id: 'StagingError', message: e.message } })
        raise e
      end

      def stage_app(app)
        if app.pending? && app.staging_task_id
          @messenger.send_stop_staging_request(app)
        end

        app.mark_for_restaging
        app.staging_task_id = VCAP.secure_uuid
        app.save_changes

        send_stage_request_for_resource(app)
      # rescue Errors::ApiError => e
      #   logger.error('stage.app', staging_guid: StagingGuid.from(app), error: e)
      #   staging_complete(StagingGuid.from(app), { error: { id: 'StagingError', message: e.message } })
      #   raise e
      end

      def staging_complete(staging_guid, staging_response)
        @completion_handler.staging_complete(staging_guid, staging_response)
      end

      private

      def logger
        @logger ||= Steno.logger('cc.stager.client')
      end

      def send_stage_request_for_resource(resource)
        @messenger.send_stage_request(resource, @staging_config)
      # rescue Errors::ApiError => e
      #   raise e
      # rescue => e
      #   raise Errors::ApiError.new_from_details('StagerError', e)
      end
    end
  end
end
