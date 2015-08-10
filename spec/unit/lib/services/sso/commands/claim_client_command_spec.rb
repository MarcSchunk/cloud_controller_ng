require 'spec_helper'

module VCAP::Services::SSO::Commands
  describe ClaimClientCommand do
    let(:client_id) { 'client-id' }
    let(:claimant) { double(:claimant) }

    let(:command) { ClaimClientCommand.new(client_id, claimant) }

    describe '#db_command' do
      before do
        allow(VCAP::CloudController::ServiceDashboardClient).to receive(:claim_client)
      end

      it 'claims the client in the DB' do
        command.db_command
        expect(VCAP::CloudController::ServiceDashboardClient).to have_received(:claim_client).with(client_id, claimant)
      end
    end
  end
end
