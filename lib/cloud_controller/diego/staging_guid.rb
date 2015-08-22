module VCAP::CloudController
  module Diego
    class StagingGuid
      ID_SEPARATOR = ':'

      def self.from(resource)
        [resource.guid, resource.staging_task_id].join(ID_SEPARATOR)
      end

      def self.resource_guid(staging_guid)
        staging_guid.split(ID_SEPARATOR)[0]
      end

      def self.staging_task_id(staging_guid)
        staging_guid.split(ID_SEPARATOR)[1]
      end
    end
  end
end
