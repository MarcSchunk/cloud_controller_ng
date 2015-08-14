require 'spec_helper'

module VCAP::CloudController
  module Services
    module Instances
      describe AfterProvision do
        let(:after_provision) { AfterProvision.new(service_instance, audit_event_params, dashboard_client_info) }
        let(:service_instance) { ManagedServiceInstance.make }
        let(:audit_event_params) { nil }
        let(:broker_response) { nil }

        before do
          service_instance.service_instance_operation = ServiceInstanceOperation.make
          service_instance.save
        end

        describe '#run' do
          context 'when there is dashboard_client_info' do
            let(:dashboard_client_info) do
              {
                id:           'client-id-1',
                secret:       'secret-1',
                redirect_uri: 'https://dashboard.service.com'
              }
            end

            it 'enqueues a client creation job' do
              expect {
                after_provision.run(broker_response)
              }.to change { Delayed::Job.count }.from(0).to(1)

              expect(Delayed::Job.first).to be_a_fully_wrapped_job_of Jobs::Services::CreateInstanceDashboardClient
            end

            it 'changes the service instance last_operation' do
              after_provision.run(broker_response)

              last_operation = service_instance.last_operation
              expect(last_operation.type).to eq('create')
              expect(last_operation.description).to eq('creating dashboard client')
              expect(last_operation.state).to eq('in progress')
            end

            context 'when queueing the dashboard create job fails' do
              let(:mock_orphan_mitigator) { double(:mock_orphan_mitigator, attempt_deprovision_instance: nil) }
              before do
                allow(SynchronousOrphanMitigate).to receive(:new).and_return(mock_orphan_mitigator)
                allow_any_instance_of(Delayed::Job).to receive(:save).and_raise
              end

              it 'attempts synchronous orphan mitigation' do
                expect {
                  after_provision.run(broker_response)
                }.to raise_error
                expect(mock_orphan_mitigator).to have_received(:attempt_deprovision_instance)
              end
            end
          end

          context 'when there is NO dashboard_client_info' do
            let(:dashboard_client_info) { nil }
            let(:event_repository) { double(:event_repository, record_service_instance_event: nil) }
            let(:audit_event_params) { CreateEventParams.new(service_instance, { fake: 'params' }) }
            let(:broker_response) do
              {
                last_operation: {
                  type: 'create',
                  state: 'succeeded',
                  description: 'meow'
                }
              }
            end

            before do
              allow(after_provision).to receive(:services_event_repository).and_return(event_repository)
            end

            it 'creates an audit event' do
              after_provision.run(broker_response)
              expect(event_repository).to have_received(:record_service_instance_event).with(:create, service_instance, { fake: 'params' })
            end

            it 'saves the last operation' do
              after_provision.run(broker_response)

              service_instance.reload
              expect(service_instance.last_operation[:state]).to eq('succeeded')
              expect(service_instance.last_operation[:description]).to eq('meow')
            end
          end
        end
      end
    end
  end
end
