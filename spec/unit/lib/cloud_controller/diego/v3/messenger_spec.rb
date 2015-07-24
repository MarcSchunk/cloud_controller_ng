require 'spec_helper'
require 'cloud_controller/diego/v3/messenger'

module VCAP::CloudController
  module Diego
    module V3
      describe Messenger do
        let(:stager_client) { instance_double(StagerClient) }
        let(:nsync_client) { instance_double(NsyncClient) }
        let(:staging_config) { TestConfig.config[:staging] }
        let(:protocol) { instance_double('Traditional::Protocol') }
        let(:default_health_check_timeout) { 9999 }
        let(:instances) { 3 }

        let(:app) { AppModel.make }
        let!(:process1) { App.make(app: app) }
        let!(:process2) { App.make(app: app) }

        subject(:messenger) { Messenger.new(stager_client, nsync_client, protocol) }

        describe '#send_desire_request' do
          let(:message) { { desire: 'message' } }

          before do
            allow(protocol).to receive(:desire_process_request).and_return(message)
            allow(nsync_client).to receive(:desire_app)
          end

          it 'sends a desire app request for each process on the app' do
            messenger.send_desire_request(app, default_health_check_timeout)

            expect(protocol).to have_received(:desire_process_request).with(process1, default_health_check_timeout)
            expect(nsync_client).to have_received(:desire_app).with(ProcessGuid.from_process(process1), message)

            expect(protocol).to have_received(:desire_process_request).with(process2, default_health_check_timeout)
            expect(nsync_client).to have_received(:desire_app).with(ProcessGuid.from_process(process2), message)
          end

          context 'when a process wants zero instances' do
            let!(:process2) { App.make(app: app, instances: 0) }

            it 'does not send any messages' do
              messenger.send_desire_request(app, default_health_check_timeout)

              expect(protocol).not_to have_received(:desire_process_request).with(process2, default_health_check_timeout)
              expect(nsync_client).not_to have_received(:desire_app).with(ProcessGuid.from_process(process2), message)
            end
          end
        end
      end
    end
  end
end
