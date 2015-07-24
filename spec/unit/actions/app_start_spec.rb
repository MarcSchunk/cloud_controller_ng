require 'spec_helper'
require 'actions/app_start'

module VCAP::CloudController
  describe AppStart do
    let(:user) { double(:user, guid: '7') }
    let(:user_email) { '1@2.3' }
    let(:runners) { double(:runners) }
    let(:runner) { double(:runner) }
    let(:app_start) { AppStart.new(user, user_email, runners) }

    describe '#start' do
      let(:environment_variables) { { 'FOO' => 'bar' } }
      let!(:process1) { App.make(state: 'STOPPED', app: app) }
      let!(:process2) { App.make(state: 'STOPPED', app: app) }
      let(:app) do
        AppModel.make({
          desired_state: 'STOPPED',
          droplet_guid: droplet_guid,
          environment_variables: environment_variables
        })
      end

      before do
        allow(runners).to receive(:runner_for_app).and_return(runner)
        allow(runner).to receive(:start)
      end

      context 'when the droplet does not exist' do
        let(:droplet_guid) { nil }

        it 'raises a DropletNotFound exception' do
          expect {
            app_start.start(app)
          }.to raise_error(AppStart::DropletNotFound)
        end
      end

      context 'when the droplet exists' do
        let(:droplet) { DropletModel.make(state: DropletModel::STAGED_STATE) }
        let(:droplet_guid) { droplet.guid }

        it 'sets the desired state on the app' do
          app_start.start(app)
          expect(app.desired_state).to eq('STARTED')
        end

        it 'asks the runner to start the app' do
          app_start.start(app)

          expect(runners).to have_received(:runner_for_app).with(app)
          expect(runner).to have_received(:start)
        end

        it 'creates an audit event' do
          expect_any_instance_of(Repositories::Runtime::AppEventRepository).to receive(:record_app_start).with(
              app,
              user.guid,
              user_email
            )

          app_start.start(app)
        end

        context 'when the app is invalid' do
          before do
            allow_any_instance_of(AppModel).to receive(:update).and_raise(Sequel::ValidationFailed.new('some message'))
          end

          it 'raises a InvalidApp exception' do
            expect {
              app_start.start(app)
            }.to raise_error(AppStart::InvalidApp, 'some message')
          end
        end
      end
    end
  end
end
