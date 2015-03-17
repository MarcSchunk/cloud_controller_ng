require 'spec_helper'
require 'awesome_print'
require 'rspec_api_documentation/dsl'

resource 'App Routes (Experimental)', type: :api do
  let(:user) { VCAP::CloudController::User.make }
  let(:user_header) { headers_for(user)['HTTP_AUTHORIZATION'] }
  header 'AUTHORIZATION', :user_header

  def do_request_with_error_handling
    do_request
    if response_status == 500
      error = MultiJson.load(response_body)
      ap error
      raise error['description']
    end
  end

  get '/v3/apps/:guid/routes' do
    let(:space) { VCAP::CloudController::Space.make }
    let(:space_guid) { space.guid }

    let!(:route1) { VCAP::CloudController::Route.make(space_guid: space_guid) }
    let!(:route2) { VCAP::CloudController::Route.make(space_guid: space_guid) }

    let(:app_model) { VCAP::CloudController::AppModel.make(space_guid: space.guid) }
    let(:guid) { app_model.guid }

    before do
      space.organization.add_user(user)
      space.add_developer(user)
      VCAP::CloudController::AppModelRoute.create(apps_v3_id: app_model.id, route_id: route1.id, type: 'web')
      VCAP::CloudController::AppModelRoute.create(apps_v3_id: app_model.id, route_id: route2.id, type: 'web')
    end

    example 'List routes' do
      do_request_with_error_handling

      expected_response = {
        'resources' => [
          {
            'guid' => route1.guid,
            'host' => route1.host,
            '_links' => {
              'space' => { 'href' => "/v2/spaces/#{space.guid}" },
              'domain' => { 'href' => "/v2/domains/#{route1.domain.guid}" }
            }
          },
          {
            'guid' => route2.guid,
            'host' => route2.host,
            '_links' => {
              'space' => { 'href' => "/v2/spaces/#{space.guid}" },
              'domain' => { 'href' => "/v2/domains/#{route2.domain.guid}" }
            }
          },
        ]
      }
      parsed_response = MultiJson.load(response_body)
      expect(response_status).to eq(200)
      expect(parsed_response).to match(expected_response)
    end
  end

  put '/v3/apps/:guid/routes' do
    parameter :route_guid, 'GUID of the route', required: true

    let(:space) { VCAP::CloudController::Space.make }
    let(:space_guid) { space.guid }

    let!(:route) { VCAP::CloudController::Route.make(space_guid: space_guid) }
    let(:route_guid) { route.guid }

    let(:app_model) { VCAP::CloudController::AppModel.make(space_guid: space.guid) }
    let(:guid) { app_model.guid }

    let(:web_process) { VCAP::CloudController::AppFactory.make(space_guid: space_guid, type: 'web') }
    let(:worker_process) { VCAP::CloudController::AppFactory.make(space_guid: space_guid, type: 'worker_process') }

    let(:raw_post) { MultiJson.dump(params, pretty: true) }

    before do
      space.organization.add_user(user)
      space.add_developer(user)
      app_model.add_process(web_process)
      app_model.add_process(worker_process)
    end

    example 'Add a Route' do
      expect {
        do_request_with_error_handling
      }.not_to change { VCAP::CloudController::App.count }

      expect(response_status).to eq(204)
      expect(app_model.routes).to eq([route])
      expect(web_process.reload.routes).to eq([route])
      expect(worker_process.reload.routes).to be_empty
    end
  end
end