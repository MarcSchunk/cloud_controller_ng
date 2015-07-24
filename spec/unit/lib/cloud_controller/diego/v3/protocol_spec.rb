require 'spec_helper'
require 'cloud_controller/diego/v3/protocol'

module VCAP::CloudController
  module Diego
    module V3
      describe Protocol do
        let(:blobstore_url_generator) do
          instance_double(CloudController::Blobstore::UrlGenerator,
            buildpack_cache_download_url:            'http://buildpack-artifacts-cache.com',
            app_package_download_url:                'http://app-package.com',
            unauthorized_perma_droplet_download_url: 'fake-droplet_uri',
            buildpack_cache_upload_url:              'http://buildpack-artifacts-cache.up.com',
            droplet_upload_url:                      'http://droplet-upload-uri',
          )
        end

        let(:default_health_check_timeout) { 9999 }
        let(:staging_config) { TestConfig.config[:staging] }
        let(:common_protocol) { double(:common_protocol) }
        let(:app) { AppModel.make }
        let(:process) { App.make(app: app) }

        subject(:protocol) do
          Protocol.new(blobstore_url_generator, common_protocol)
        end

        before do
          allow(common_protocol).to receive(:staging_egress_rules).and_return(['staging_egress_rule'])
          allow(common_protocol).to receive(:running_egress_rules).with(app).and_return(['running_egress_rule'])
        end

        describe '#desire_app_request' do
          let(:request) { protocol.desire_process_request(process, default_health_check_timeout) }

          it 'returns the message' do
            expect(request).to match_json(protocol.desire_process_message(process, default_health_check_timeout))
          end
        end

        describe '#desire_process_message' do
          let(:process) do
            AppFactory.make(
              instances:            111,
              disk_quota:           222,
              file_descriptors:     333,
              guid:                 'fake-guid',
              command:              'the-custom-command',
              health_check_type:    'port',
              health_check_timeout: 10,
              memory:               100,
              stack:                Stack.make(name: 'fake-stack'),
              enable_ssh:           true,
              app:                  app
            )
          end
          let(:route) { Route.make(space: process.space) }

          let(:message) { protocol.desire_process_message(process, default_health_check_timeout) }

          before do
            process.add_route(route)
            process.reload
            environment = instance_double(Environment, as_json: [{ 'name' => 'fake', 'value' => 'environment' }])
            allow(V3::Environment).to receive(:new).with(process).and_return(environment)
          end

          it 'is a messsage with the information nsync needs to desire the app' do
            expect(message).to eq({
                  'disk_mb'                         => 222,
                  'droplet_uri'                     => 'fake-droplet_uri',
                  'environment'                     => [{ 'name' => 'fake', 'value' => 'environment' }],
                  'file_descriptors'                => 333,
                  'health_check_type'               => 'port',
                  'health_check_timeout_in_seconds' => 10,
                  'log_guid'                        => app.guid,
                  'memory_mb'                       => 100,
                  'num_instances'                   => 111,
                  'process_guid'                    => ProcessGuid.from_process(process),
                  'stack'                           => 'fake-stack',
                  'start_command'                   => 'the-custom-command',
                  'execution_metadata'              => '',
                  'routes'                          => [route.fqdn],
                  'egress_rules'                    => ['running_egress_rule'],
                  'etag'                            => process.updated_at.to_f.to_s,
                  'allow_ssh'                       => true,
                })
          end

          context 'when the app health check timeout is not set' do
            before do
              TestConfig.override(default_health_check_timeout: default_health_check_timeout)
            end

            let(:process) { AppFactory.make(health_check_timeout: nil, app: app) }

            it 'uses the default app health check from the config' do
              expect(message['health_check_timeout_in_seconds']).to eq(default_health_check_timeout)
            end
          end
        end
      end
    end
  end
end
