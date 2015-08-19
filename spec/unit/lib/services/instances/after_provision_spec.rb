require 'spec_helper'

module VCAP::CloudController
  module Services
    module Instances
      describe AfterProvision do
        let(:after_provision) { AfterProvision.new(service_instance, audit_event_params, dashboard_client_info, event_repository) }
        let(:service_instance) { ManagedServiceInstance.make }
        let(:audit_event_params) { nil }
        let(:broker_response) { nil }
        let(:event_repository) { double(:event_repository, record_service_instance_event: nil) }

        before do
          service_instance.service_instance_operation = ServiceInstanceOperation.make
          service_instance.save
          service_instance.update(dashboard_url: 'http://dashboard.com')
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


            # it 'changes the service instance last_operation' do
            #   after_provision.run(broker_response)
            #
            #   last_operation = service_instance.last_operation
            #   expect(last_operation.type).to eq('create')
            #   expect(last_operation.description).to eq('creating dashboard client')
            #   expect(last_operation.state).to eq('in progress')
            # end


            # context 'when queueing the dashboard create job fails' do
            #   let(:mock_orphan_mitigator) { double(:mock_orphan_mitigator, attempt_deprovision_instance: nil) }
            #   before do
            #     allow(SynchronousOrphanMitigate).to receive(:new).and_return(mock_orphan_mitigator)
            #     allow_any_instance_of(Delayed::Job).to receive(:save).and_raise
            #   end
            #
            #   it 'attempts synchronous orphan mitigation' do
            #     expect {
            #       after_provision.run(broker_response)
            #     }.to raise_error
            #     expect(mock_orphan_mitigator).to have_received(:attempt_deprovision_instance)
            #   end
            # end

            context 'when no dashboard_url is passed' do
              before do
                service_instance.update(dashboard_url: nil)
              end

              it 'enqueues an orphan mitigation job' do
                after_provision.run(broker_response)

                expect(Delayed::Job.count).to eq 1
                expect(Delayed::Job.first).to be_a_fully_wrapped_job_of(VCAP::CloudController::Jobs::Services::DeleteOrphanedInstance)
              end

              it 'sets the last_operation to failed' do
                after_provision.run(broker_response)

                service_instance.reload
                expect(service_instance.last_operation.state).to eq('failed')
                expect(service_instance.last_operation.description).to eq('Missing dashboard_url from broker response; dashboard_url is required when dashboard_client is provided')
              end
            end




            let(:client_manager) { double(:client_manager, add_client_for_instance: true) }

            before do
              allow(VCAP::Services::SSO::DashboardClientManager).to receive(:new).and_return(client_manager)
            end

            it 'builds the dashboard client with the correct values' do
              after_provision.run(broker_response)

              expect(VCAP::Services::SSO::DashboardClientManager).to have_received(:new).with(instance, event_repository)
            end

            it 'adds a client for the instance' do
              after_provision.run(broker_response)

              expect(client_manager).to have_received(:add_client_for_instance).with(dashboard_client_info)
            end

            it 'records an instance create audit event' do
              after_provision.run(broker_response)

              expect(event_repository).to have_received(:record_service_instance_event).with(*audit_event_params.params)
            end

            it 'sets the last operation to succeeded' do
              after_provision.run(broker_response)

              instance.reload
              expect(instance.last_operation.state).to eq('succeeded')
              expect(instance.last_operation.description).to eq('created client for service instance dashboard SSO')
            end

            context 'when adding the client fails' do
              let(:messages) { ['error1', 'error2'] }

              before do
                allow(client_manager).to receive(:add_client_for_instance).and_return(false)
                errors = double(:errors)
                allow(client_manager).to receive(:errors).and_return(errors)
                allow(errors).to receive(:messages).and_return(messages)
              end

              it 'marks the operation as failed and updates the description with the error' do
                after_provision.run(broker_response)

                instance.reload
                expect(instance.last_operation.state).to eq('failed')
                expect(instance.last_operation.description).to eq('error1, error2')
              end

              it 'enqueues an orphan mitigation job' do
                after_provision.run(broker_response)

                expect(Delayed::Job.count).to eq 1
                expect(Delayed::Job.first).to be_a_fully_wrapped_job_of(DeleteOrphanedInstance)
              end
            end
          end

          context 'when there is NO dashboard_client_info' do
            let(:dashboard_client_info) { nil }
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

            it 'creates an audit event' do
              after_provision.run(broker_response)
              expect(event_repository).to have_received(:record_service_instance_event).with(:create, service_instance, { fake: 'params' })
            end

            it 'saves the last operation returned from the broker' do
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
