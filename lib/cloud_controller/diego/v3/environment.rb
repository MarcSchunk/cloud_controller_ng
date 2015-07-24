module VCAP::CloudController
  module Diego
    module V3
      class Environment
        attr_reader :process

        def initialize(process)
          @process = process
        end

        def as_json
          env = []
          env << { 'name' => 'MEMORY_LIMIT', 'value' => "#{process.memory}m" }
          env << { 'name' => 'CF_STACK', 'value' => "#{process.stack.name}" }

          app_env_json = process.app.environment_variables || {}
          app_env_json.each do |k, v|
            case v
              when Array, Hash
                v = MultiJson.dump(v)
              else
                v = v.to_s
            end

            env << { 'name' => k, 'value' => v }
          end

          env
        end
      end
    end
  end
end
