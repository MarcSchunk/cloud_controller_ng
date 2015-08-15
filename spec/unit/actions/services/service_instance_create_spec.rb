require 'spec_helper'
require 'actions/services/service_instance_create'

module VCAP::CloudController
  describe ServiceInstanceCreate do
    let(:logger) { double(:logger) }
    let(:after_provision) { double(:after_provision, run: nil) }
    let(:warning_observer) { double(:warning_observer) }
    let(:event_repository) { nil }
    subject(:create_action) { ServiceInstanceCreate.new(logger, warning_observer, event_repository) }

    before do
      allow(VCAP::CloudController::Services::Instances::AfterProvision).to receive(:new).and_return(after_provision)
      allow(VCAP::Services::SSO::DashboardClientManager).to receive(:cc_configured_to_modify_uaa_clients?).and_return(true)
    end

    describe '#create' do
      let(:space) { Space.make }
      let(:service_plan) { ServicePlan.make }
      let(:request_attrs) do
        {
          'space_guid'        => space.guid,
          'service_plan_guid' => service_plan.guid,
          'name'              => 'my-instance',
        }
      end

      before do
        stub_provision(service_plan.service.service_broker)
      end

      it 'creates the service instance with the requested params' do
        expect {
          create_action.create(request_attrs, false)
        }.to change { ServiceInstance.count }.from(0).to(1)
        service_instance = ServiceInstance.where(name: 'my-instance').first
        expect(service_instance.credentials).to eq({})
        expect(service_instance.space.guid).to eq(space.guid)
        expect(service_instance.service_plan.guid).to eq(service_plan.guid)
      end

      it 'creates a new service instance operation' do
        create_action.create(request_attrs, false)
        expect(ManagedServiceInstance.last.last_operation).to eq(ServiceInstanceOperation.last)
      end

      context 'when the service instance create returns dashboard client credentials' do
        let(:body) do
          {
            dashboard_url:    'http://example-dashboard.com/9189kdfsk0vfnku',
            dashboard_client: {
              id:           'client-id-1',
              secret:       'secret-1',
              redirect_uri: 'https://dashboard.service.com'
            }
          }.to_json
        end
        let(:accepts_incomplete) { false } # this value doesn't matter for this test

        context 'and the broker response is synchronous with code 201' do
          before do
            stub_provision(service_plan.service.service_broker, body: body, status: 201)
          end

          it 'runs the after provision' do
            create_action.create(request_attrs, accepts_incomplete)

            expect(after_provision).to have_received(:run)
          end
        end

        context 'and the broker response is asynchronous with code 202' do
          let(:accepts_incomplete) { true }

          before do
            stub_provision(service_plan.service.service_broker, body: body, status: 202, accepts_incomplete: true)
          end

          it 'creates a state fetch job with the after provision' do
            allow(Jobs::Services::InstanceAsyncWatcher).to receive(:new).and_call_original

            service_instance = nil
            expect {
              service_instance = create_action.create(request_attrs, true)
            }.to change { Delayed::Job.count }.from(0).to(1)

            job = Delayed::Job.first
            expect(job).to be_a_fully_wrapped_job_of(Jobs::Services::InstanceAsyncWatcher)

            expect(Jobs::Services::InstanceAsyncWatcher).to have_received(:new).
                with(service_instance.guid, after_provision)
          end
        end

        context 'and SSO is disabled in CC' do
          before do
            stub_provision(service_plan.service.service_broker, body: body, status: 201, accepts_incomplete: true)
            allow(VCAP::Services::SSO::DashboardClientManager).to receive(:cc_configured_to_modify_uaa_clients?).and_return(false)
            allow(warning_observer).to receive(:add_warning)
          end

          it 'adds a warning to the warning observer' do
            create_action.create(request_attrs, true)

            expect(warning_observer).to have_received(:add_warning).with(/Warning: The broker requested a dashboard client./)
          end

          it 'nils the dashboard_client_info so no creation attempt occurs' do
            create_action.create(request_attrs, true)

            expect(VCAP::CloudController::Services::Instances::AfterProvision).to have_received(:new).with(anything, anything, nil, anything)
          end
        end
      end

      context 'when there are arbitrary params' do
        let(:parameters) { { 'some-param' => 'some-value' } }
        let(:request_attrs) do
          {
            'space_guid'        => space.guid,
            'service_plan_guid' => service_plan.guid,
            'name'              => 'my-instance',
            'parameters'        => parameters
          }
        end

        it 'passes the params to the client' do
          create_action.create(request_attrs, false)
          expect(a_request(:put, /.*/).with(body: hash_including({ parameters: parameters }))).to have_been_made
        end
      end

      context 'with accepts_incomplete' do
        before do
          stub_provision(service_plan.service.service_broker, accepts_incomplete: true, status: 202)
        end

        it 'enqueues a async job' do
          expect {
            create_action.create(request_attrs, true)
          }.to change { Delayed::Job.count }.from(0).to(1)

          expect(Delayed::Job.first).to be_a_fully_wrapped_job_of Jobs::Services::InstanceAsyncWatcher
        end
      end

      context 'when the instance fails to save to the db' do
        let(:mock_orphan_mitigator) { double(:mock_orphan_mitigator, attempt_deprovision_instance: nil) }
        before do
          allow(SynchronousOrphanMitigate).to receive(:new).and_return(mock_orphan_mitigator)
          allow_any_instance_of(ManagedServiceInstance).to receive(:save).and_raise
          allow(logger).to receive(:error)
        end

        it 'attempts synchronous orphan mitigation' do
          expect {
            create_action.create(request_attrs, false)
          }.to raise_error
          expect(mock_orphan_mitigator).to have_received(:attempt_deprovision_instance)
        end

        it 'logs that it was unable to save' do
          create_action.create(request_attrs, false) rescue nil

          expect(logger).to have_received(:error).with /Failed to save/
        end
      end
    end
  end
end
