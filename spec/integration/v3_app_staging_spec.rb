require 'spec_helper'
require 'securerandom'

describe 'using diego to stage', type: :integration do
  before do
    start_cc(debug: false, config: 'spec/fixtures/config/port_8181_config.yml')
    @tmpdir = Dir.mktmpdir
  end

  after do
    stop_cc
  end

  context 'when admin buildpacks are used' do
    let(:stager_id) { 'abc123' }
    let(:advertisment) do
      {
        'id' => stager_id,
        'stacks' => ['cflinuxfs2'],
        'available_memory' => 2048,
      }.to_json
    end

    let(:auth_headers) do
      {
        'Authorization' => "bearer #{admin_token}",
        'Accept' => 'application/json',
        'Content-Type' => 'application/json'
      }
    end

    def valid_zip(size=1)
      @valid_zip ||= {}
      @valid_zip[size.to_s] ||= begin
        zip_name = File.join(@tmpdir, "file_#{size}.zip")
        TestZip.create(zip_name, size, 1024)
        File.new(zip_name)
      end
    end

    before do
      # WebMock.allow_net_connect!

      @buildpack_response_1 = make_post_request(
        '/v2/buildpacks',
        { 'name' => 'buildpack-1', 'position' => 2 }.to_json,
        auth_headers
      )

      @buildpack_response_2 = make_post_request(
        '/v2/buildpacks',
        { 'name' => 'buildpack-2', 'position' => 1 }.to_json,
        auth_headers
      )

      @expected_buildpack_shas = [
        "#{@buildpack_response_2.json_body['metadata']['guid']}_#{valid_zip.hexdigest}",
        "#{@buildpack_response_1.json_body['metadata']['guid']}_#{valid_zip(4).hexdigest}",
      ]

      org = make_post_request(
        '/v2/organizations',
        { 'name' => "foo_org-#{SecureRandom.uuid}" }.to_json,
        auth_headers
      )

      space = make_post_request(
        '/v2/spaces',
        {
          'name' => 'foo_space',
          'organization_guid' => org.json_body['metadata']['guid']
        }.to_json,
        auth_headers
      )

      @app_response = make_post_request(
        '/v2/apps',
        {
          'name' => 'foobar'et

          'memory' => 64,
          'instances' => 2,
          'disk_quota' => 1024,
          'space_guid' => space.json_body['metadata']['guid'],
          'diego' => true,
          'state' => 'STOPPED',
        }.to_json,
        auth_headers
      )

      @app_bits_response = make_put_request(
        "/v2/apps/#{@app_response.json_body['metadata']['guid']}/bits?application[tempfile]=#{valid_zip(2).path}&resources=[]",
        '{}',
        auth_headers
      )
    end

    context 'and the admin has uploaded the buildpacks' do
      before do
        @buildpack_bits_response_1 = make_put_request(
          "/v2/buildpacks/#{@buildpack_response_1.json_body['metadata']['guid']}/bits?buildpack[tempfile]=#{valid_zip(4).path}&buildpack_name=foo.zip",
          '{}',
          auth_headers
        )

        @buildpack_bits_response_2 = make_put_request(
          "/v2/buildpacks/#{@buildpack_response_2.json_body['metadata']['guid']}/bits?buildpack[tempfile]=#{valid_zip.path}&buildpack_name=bar.zip",
          '{}',
          auth_headers
        )
      end

      context 'a v2 app' do
        fit 'sends the correct request to cc bridge' do
          response = make_put_request(
            "/v2/apps/#{@app_response.json_body['metadata']['guid']}",
            {
              'state' => 'STARTED',
            }.to_json,
            auth_headers
          )
          binding.pry

          expect(Diego::Something).to receive_request("blah")
        end
      end
    end
  end
end
