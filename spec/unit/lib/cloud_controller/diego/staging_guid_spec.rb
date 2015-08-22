require 'spec_helper'
require 'cloud_controller/diego/staging_guid'

module VCAP::CloudController::Diego
  describe StagingGuid do
    let(:app) do
      VCAP::CloudController::AppFactory.make(staging_task_id: Sham.guid)
    end

    describe 'from' do
      it 'returns the appropriate versioned guid for a resource' do
        expect(StagingGuid.from(app)).to eq("#{app.guid}:#{app.staging_task_id}")
      end
    end

    describe 'resource_guid' do
      it 'it returns the guid of the resource from the staging guid' do
        expect(StagingGuid.resource_guid(StagingGuid.from(app))).to eq(app.guid)
      end
    end

    describe 'staging_task_id' do
      it 'it returns the staging task id from the staging guid' do
        expect(StagingGuid.staging_task_id(StagingGuid.from(app))).to eq(app.staging_task_id)
      end
    end
  end
end
