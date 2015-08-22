require 'spec_helper'

module VCAP::CloudController
  module Diego
    describe Stager do
      let(:messenger) { instance_double(Messenger, send_desire_request: nil) }
      let(:app) { AppFactory.make }
      let(:package) { PackageModel.make(app: app) }
      let(:staging_config) { TestConfig.config[:stager] }
      let(:completion_handler) do
        instance_double(Diego::Traditional::StagingCompletionHandler, staging_complete: nil)
      end

      subject(:stager) do
        Stager.new(messenger, completion_handler, staging_config)
      end

      describe "#stage_package" do
        before do
          allow(messenger).to receive(:send_stage_request)
          allow(messenger).to receive(:send_stop_staging_request)
        end

        it 'notifies Diego that the package needs staging' do
          expect(messenger).to receive(:send_stage_request).with(package, staging_config)
          stager.stage_package(package)
        end

        context 'when the package is not currently staging' do
          before do
            package.staging_task_id = nil
          end

          it 'does not attempt to stop the outstanding stage request' do
            expect(messenger).to_not receive(:send_stop_staging_request)
            stager.stage_package(package)
          end
        end

        context 'when the package is already staging' do
          before do
            package.staging_task_id = Sham.guid
          end

          it 'attempts to stop the outstanding stage request' do
            expect(messenger).to receive(:send_stop_staging_request).with(package)
            stager.stage_package(package)
          end
        end

        context 'when the stage fails' do
          let(:error) do
            { error: { id: 'StagingError', message: 'Stager error: staging failed' } }
          end

          before do
            allow(messenger).to receive(:send_stage_request).and_raise Errors::ApiError.new_from_details('StagerError', 'staging failed')
            allow(stager).to receive(:staging_complete)
          end

          it 'attempts to stop the outstanding stage request' do
            expect { stager.stage_package(package) }.to raise_error(Errors::ApiError)
            package.reload
            expect(stager).to have_received(:staging_complete).with(StagingGuid.from(package), error)
          end
        end
      end

      describe '#stage_app' do
        before do
          allow(messenger).to receive(:send_stage_request)
          allow(messenger).to receive(:send_stop_staging_request)
        end

        it 'notifies Diego that the app needs staging' do
          expect(app).to receive(:mark_for_restaging)
          expect(messenger).to receive(:send_stage_request).with(app, staging_config)
          stager.stage_app(app)
        end

        context 'when there is a pending stage' do
          context 'when a staging task id is nil' do
            before do
              app.staging_task_id = nil
            end

            it 'does not attempt to stop the outstanding stage request' do
              expect(messenger).to_not receive(:send_stop_staging_request)
              stager.stage_app(app)
            end
          end

          context 'when a staging task id is not nil' do
            before do
              app.staging_task_id = Sham.guid
            end

            it 'attempts to stop the outstanding stage request' do
              expect(messenger).to receive(:send_stop_staging_request).with(app)
              stager.stage_app(app)
            end
          end
        end

        context 'when the stage fails' do
          let(:error) do
            { error: { id: 'StagingError', message: 'Stager error: staging failed' } }
          end

          before do
            allow(messenger).to receive(:send_stage_request).and_raise Errors::ApiError.new_from_details('StagerError', 'staging failed')
            allow(stager).to receive(:staging_complete)
          end

          it 'attempts to stop the outstanding stage request' do
            expect { stager.stage_app(app) }.to raise_error(Errors::ApiError)
            app.reload
            expect(stager).to have_received(:staging_complete).with(StagingGuid.from(app), error)
          end
        end
      end

      describe '#staging_complete' do
        let(:staging_guid) { 'a-staging-guid' }
        let(:staging_response) { { app_id: 'app-id' } }

        before do
          allow(completion_handler).to receive(:staging_complete)

          stager.staging_complete(staging_guid, staging_response)
        end

        it 'delegates to the staging completion handler' do
          expect(completion_handler).to have_received(:staging_complete).with(staging_guid, staging_response)
        end
      end
    end
  end
end
