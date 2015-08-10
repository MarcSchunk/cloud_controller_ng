module VCAP::Services::SSO::Commands
  class ClaimClientCommand
    attr_reader :client_id, :claimant

    def initialize(client_id, claimant)
      @client_id = client_id
      @claimant = claimant
    end

    def db_command
      VCAP::CloudController::ServiceDashboardClient.claim_client(client_id, claimant)
    end
  end
end
