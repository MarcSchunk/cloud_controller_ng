require 'cloud_controller/diego/v3/environment'
require 'cloud_controller/diego/process_guid'

module VCAP::CloudController
  module Diego
    module V3
      class Protocol
        def initialize(blobstore_url_generator, common_protocol)
          @blobstore_url_generator   = blobstore_url_generator
          @common_protocol           = common_protocol
        end

        def desire_process_request(process, default_health_check_timeout)
          desire_process_message(process, default_health_check_timeout).to_json
        end

        def desire_process_message(process, default_health_check_timeout)
          message = {
            'process_guid'                    => ProcessGuid.from_process(process),
            'memory_mb'                       => process.memory,
            'disk_mb'                         => process.disk_quota,
            'file_descriptors'                => process.file_descriptors,
            'droplet_uri'                     => @blobstore_url_generator.unauthorized_perma_droplet_download_url(process.app),
            'stack'                           => process.stack.name,
            'start_command'                   => process.command,
            'execution_metadata'              => '',
            'environment'                     => Environment.new(process).as_json,
            'num_instances'                   => process.instances,
            'routes'                          => process.uris,
            'log_guid'                        => process.app_guid,
            'health_check_type'               => process.health_check_type,
            'health_check_timeout_in_seconds' => process.health_check_timeout || default_health_check_timeout,
            'egress_rules'                    => @common_protocol.running_egress_rules(process.app),
            'etag'                            => process.updated_at.to_f.to_s,
            'allow_ssh'                       => process.enable_ssh,
          }

          message
        end
      end
    end
  end
end
