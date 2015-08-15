require 'spec_helper'

module VCAP::CloudController
  describe ServiceDashboardClient do
    let(:service_broker) { ServiceBroker.make }
    let(:other_broker) { ServiceBroker.make }
    let(:service_instance) { ManagedServiceInstance.make }
    let(:other_instance) { ManagedServiceInstance.make }
    let(:uaa_id) { 'claimed_client_id' }

    it { is_expected.to have_timestamp_columns }

    describe 'Validations' do
      it { is_expected.to validate_presence :uaa_id }
      it { is_expected.to validate_uniqueness :uaa_id }
    end

    describe '.find_clients_claimed_by' do
      before do
        ServiceDashboardClient.claim_client('client-1', service_broker)
        ServiceDashboardClient.claim_client('client-2', other_broker)
        ServiceDashboardClient.claim_client('client-3', service_instance)
        ServiceDashboardClient.claim_client('client-4', other_instance)
        ServiceDashboardClient.claim_client('client-5', service_broker)
        ServiceDashboardClient.claim_client('client-6', service_instance)
      end

      it 'returns all clients claimed by the broker' do
        results = ServiceDashboardClient.find_clients_claimed_by(service_broker)
        expect(results).to have(2).entries
        expect(results.map(&:uaa_id)).to match_array ['client-1', 'client-5']
      end
    end

    describe '.claim_client' do
      context 'when the client is unclaimed' do
        it 'creates a new client claim entry owned by the claimant' do
          expect(
            ServiceDashboardClient.
              where(uaa_id: uaa_id, claimant_guid: service_broker.guid).
              count
          ).to eq(0)

          ServiceDashboardClient.claim_client(uaa_id, service_broker)

          expect(
            ServiceDashboardClient.
              where(uaa_id: uaa_id, claimant_guid: service_broker.guid).
              count
          ).to eq(1)
        end
      end

      context 'when a claim without a claimant guid exists' do
        before do
          ServiceDashboardClient.make(claimant_guid: nil, uaa_id: uaa_id)
        end

        it 'assigns the existing claim to the claimant' do
          client_id = ServiceDashboardClient.find(uaa_id: uaa_id, claimant_guid: nil).id

          ServiceDashboardClient.claim_client(uaa_id, service_broker)

          expect(
            ServiceDashboardClient.find(uaa_id: uaa_id, claimant_guid: service_broker.guid).id
          ).to eq(client_id)
        end
      end

      context 'when the client is already claimed by another claimant' do
        before do
          ServiceDashboardClient.claim_client(uaa_id, other_broker)
        end

        it 'raises an exception' do
          expect {
            ServiceDashboardClient.claim_client(uaa_id, service_broker)
          }.to raise_exception(Sequel::ValidationFailed)
        end
      end

      context 'when the client is already claimed by this claimant' do
        before do
          ServiceDashboardClient.claim_client(uaa_id, service_broker)
        end

        it 'makes no changes to claims' do
          client_id = ServiceDashboardClient.find(uaa_id: uaa_id, claimant_guid: service_broker.guid).id
          original_count = ServiceDashboardClient.count

          ServiceDashboardClient.claim_client(uaa_id, service_broker)

          expect(
            ServiceDashboardClient.find(uaa_id: uaa_id, claimant_guid: service_broker.guid).id
          ).to eq(client_id)
          expect(ServiceDashboardClient.count).to eq(original_count)
        end
      end
    end

    describe '.remove_claim' do
      before do
        ServiceDashboardClient.claim_client(uaa_id, service_broker)
      end

      it 'removes the claim' do
        expect(ServiceDashboardClient.where(uaa_id: uaa_id).count).to eq(1)

        ServiceDashboardClient.remove_claim(uaa_id)

        expect(ServiceDashboardClient.where(uaa_id: uaa_id).count).to eq(0)
      end
    end

    describe '.find_client_by_uaa_id' do
      context 'when no clients with the specified uaa_id exist' do
        it 'returns nil' do
          expect(ServiceDashboardClient.find_client_by_uaa_id('some-uaa-id')).to be_nil
        end
      end

      context 'when one client exists with the specified uaa_id' do
        let!(:client) {
          ServiceDashboardClient.make(uaa_id: 'some-uaa-id', claimant_guid: nil)
        }

        it 'returns the client' do
          expect(ServiceDashboardClient.find_client_by_uaa_id('some-uaa-id')).to eq(client)
        end
      end
    end
  end
end
