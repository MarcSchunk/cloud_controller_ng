require 'spec_helper'
require 'jobs/services/create_instance_dashboard_client'

module VCAP::CloudController
  module Jobs
    module Services
      describe CreateInstanceDashboardClient do
        let(:instance) { ManagedServiceInstance.make }
        let(:dashboard_client_info) { double(:client_info) }
        let(:event_repository) { double(:event_repository, record_service_instance_event: nil) }
        let(:audit_event_params) { VCAP::CloudController::Services::Instances::CreateEventParams.new(instance, { fake: 'params' }) }

        subject(:job) do
          VCAP::CloudController::Jobs::Services::CreateInstanceDashboardClient.new(instance.guid, dashboard_client_info, audit_event_params, event_repository)
        end

        before do
          instance.service_instance_operation = ServiceInstanceOperation.make(type: 'create', state: 'in progress')
          instance.save
        end

        describe '#perform' do
          let(:client_manager) { double(:client_manager, add_client_for_instance: true) }

          before do
            allow(VCAP::Services::SSO::DashboardClientManager).to receive(:new).and_return(client_manager)
          end

          it 'builds the dashboard client with the correct values' do
            job.perform

            expect(VCAP::Services::SSO::DashboardClientManager).to have_received(:new).with(instance, event_repository)
          end

          it 'adds a client for the instance' do
            job.perform

            expect(client_manager).to have_received(:add_client_for_instance).with(dashboard_client_info)
          end

          it 'records an instance create audit event' do
            job.perform

            expect(event_repository).to have_received(:record_service_instance_event).with(*audit_event_params.params)
          end

          it 'sets the last operation to succeeded' do
            job.perform

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
              job.perform

              instance.reload
              expect(instance.last_operation.state).to eq('failed')
              expect(instance.last_operation.description).to eq('error1, error2')
            end

            it 'enqueues an orphan mitigation job' do
              job.perform

              expect(Delayed::Job.count).to eq 1
              expect(Delayed::Job.first).to be_a_fully_wrapped_job_of(DeleteOrphanedInstance)
            end
          end
        end

        describe '#job_name_in_configuration' do
          it 'returns the name of the job' do
            expect(job.job_name_in_configuration).to eq(:create_instance_dashboard_client)
          end
        end
      end
    end
  end
end
