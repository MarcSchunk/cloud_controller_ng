require 'cloud_controller/diego/traditional/buildpack_entry_generator'
require 'cloud_controller/diego/environment'
require 'cloud_controller/diego/process_guid'
require 'cloud_controller/diego/staging_request'
require 'cloud_controller/diego/traditional/lifecycle_data'

module VCAP::CloudController
  module Diego
    module Traditional
      class Protocol
        def initialize(blobstore_url_generator, egress_rules)
          @blobstore_url_generator = blobstore_url_generator
          @buildpack_entry_generator = BuildpackEntryGenerator.new(@blobstore_url_generator)
          @egress_rules = egress_rules
        end

        def stage_app_request(app, staging_config)
          stage_app_message(app, staging_config).to_json
        end

        def desire_app_request(app, default_health_check_timeout)
          desire_app_message(app, default_health_check_timeout).to_json
        end

        def staging_details(resource)
          case resource.class
            when VCAP::CloudController::App
              app_staging_details(resource)
            when VCAP::CloudController::PackageModel
              package_staing_details(resource)
            else
              raise
          end
        end

        def app_staging_details(app)
          {
            app_bits_download_uri: @blobstore_url_generator.app_package_download_url(app),
            build_artifacts_cache_download_uri: @blobstore_url_generator.buildpack_cache_download_url(app),
            build_artifacts_cache_upload_uri: @blobstore_url_generator.buildpack_cache_upload_url(app),
            droplet_upload_uri: @blobstore_url_generator.droplet_upload_url(app),
            buildpacks: @buildpack_entry_generator.buildpack_entries(app),
            stack: app.stack.name,
            guid: app.guid
          }
        end

        def stage_resource_message(resource, staging_config)
          resource_staging_details = staging_details(resource)
          # v2 app
          lifecycle_data = LifecycleData.new
          lifecycle_data.app_bits_download_uri = resource_staging_details.app_bits_download_uri
          lifecycle_data.build_artifacts_cache_download_uri = resource_staging_details.build_artifacts_cache_download_uri
          lifecycle_data.build_artifacts_cache_upload_uri = resource_staging_details.build_artifacts_cache_download_uri
          lifecycle_data.droplet_upload_uri = resource_staging_details.droplet_upload_uri
          lifecycle_data.buildpacks = resource_staging_details.buildpacks
          lifecycle_data.stack = resource_staging_details.stack

          staging_request = StagingRequest.new
          staging_request.app_id = resource_staging_details.guid
          staging_request.log_guid = resource_staging_details.guid
          staging_request.environment = Environment.new(app, EnvironmentVariableGroup.staging.environment_json).as_json
          staging_request.memory_mb = [app.memory, staging_config[:minimum_staging_memory_mb]].max
          staging_request.disk_mb = [app.disk_quota, staging_config[:minimum_staging_disk_mb]].max
          staging_request.file_descriptors = [app.file_descriptors, staging_config[:minimum_staging_file_descriptor_limit]].max
          staging_request.egress_rules = @egress_rules.staging
          staging_request.timeout = staging_config[:timeout_in_seconds]
          staging_request.lifecycle = 'buildpack'
          staging_request.lifecycle_data = lifecycle_data.message

          staging_request.message
        end

        def desire_app_message(app, default_health_check_timeout)
          message = {
            'process_guid' => ProcessGuid.from_app(app),
            'memory_mb' => app.memory,
            'disk_mb' => app.disk_quota,
            'file_descriptors' => app.file_descriptors,
            'stack' => app.stack.name,
            'start_command' => app.command,
            'execution_metadata' => app.execution_metadata,
            'environment' => Environment.new(app, EnvironmentVariableGroup.running.environment_json).as_json,
            'num_instances' => app.desired_instances,
            'routes' => app.uris,
            'log_guid' => app.guid,
            'health_check_type' => app.health_check_type,
            'health_check_timeout_in_seconds' => app.health_check_timeout || default_health_check_timeout,
            'egress_rules' => @egress_rules.running(app),
            'etag' => app.updated_at.to_f.to_s,
            'allow_ssh' => app.enable_ssh,
            'droplet_uri' => @blobstore_url_generator.unauthorized_perma_droplet_download_url(app),
          }

          message
        end
      end
    end
  end
end
