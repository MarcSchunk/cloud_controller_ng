require 'spec_helper'
require 'cloud_controller/diego/v3/environment'

module VCAP::CloudController
  module Diego::V3
    describe Environment do
      let(:process) { App.make(app: app) }
      let(:app) { AppModel.make }
      let(:environment) do
        {
          APP_KEY1: 'APP_VAL1',
          APP_KEY2: { nested: 'data' },
          APP_KEY3: [1, 2, 3],
          APP_KEY4: 1,
          APP_KEY5: true,
        }
      end

      before do
        app.environment_variables = environment
        app.save
      end

      it 'returns the correct environment hash for a process' do
        expect(Environment.new(process).as_json).to eq([
              { 'name' => 'MEMORY_LIMIT', 'value' => "#{process.memory}m" },
              { 'name' => 'CF_STACK', 'value' => "#{process.stack.name}" },
              { 'name' => 'APP_KEY1', 'value' => 'APP_VAL1' },
              { 'name' => 'APP_KEY2', 'value' => '{"nested":"data"}' },
              { 'name' => 'APP_KEY3', 'value' => '[1,2,3]' },
              { 'name' => 'APP_KEY4', 'value' => '1' },
              { 'name' => 'APP_KEY5', 'value' => 'true' },
            ])
      end
    end
  end
end
