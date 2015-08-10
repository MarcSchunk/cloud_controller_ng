module VCAP::CloudController
  class ServiceDashboardClient < Sequel::Model
    def self.claim_client(uaa_id, claimant)
      client = find_client_by_uaa_id(uaa_id)

      return if client && client.claimed_by?(claimant)

      if client && client.unclaimed?
        client.update(claimant_guid: claimant.guid)
      else
        create(uaa_id: uaa_id, claimant_guid: claimant.guid)
      end
    end

    def self.find_clients_claimed_by(claimant)
      where(claimant_guid: claimant.guid)
    end

    def self.remove_claim(uaa_id)
      where(uaa_id: uaa_id).delete
    end

    def self.find_client_by_uaa_id(uaa_id)
      where(uaa_id: uaa_id).first
    end

    def validate
      validates_presence :uaa_id
      validates_unique :uaa_id
    end

    def unclaimed?
      claimant_guid == nil
    end

    def claimed_by?(claimant)
      claimant_guid == claimant.guid
    end
  end
end
