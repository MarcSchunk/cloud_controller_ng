module VCAP::CloudController
  module Services
    module Instances
      class CreateEventParams
        def initialize(instance, request_attrs)
          @instance      = instance
          @request_attrs = request_attrs
        end

        def params
          [:create, @instance, @request_attrs]
        end
      end
    end
  end
end
