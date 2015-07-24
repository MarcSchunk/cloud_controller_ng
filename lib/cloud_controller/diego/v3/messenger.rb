module VCAP::CloudController
  module Diego
    module V3
    class Messenger
      def initialize(stager_client, nsync_client, protocol)
        @nsync_client = nsync_client
        @protocol = protocol
      end

      def send_desire_request(app, default_health_check_timeout)
        logger.info('desire.app.begin', app_guid: app.guid)

        app.processes.each do |process|
          next if process.instances == 0

          lrp_guid = ProcessGuid.from_process(process)

          logger.info('desire.app.process', app_guid: app.guid, process_guid: process.guid, lrp_guid: lrp_guid)
          desire_message = @protocol.desire_process_request(process, default_health_check_timeout)
          @nsync_client.desire_app(lrp_guid, desire_message)
        end
      end

      private

      def logger
        @logger ||= Steno.logger('cc.diego.v3.messenger')
      end
    end
  end
end
end
