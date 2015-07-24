require 'actions/procfile_parse'

module VCAP::CloudController
  class AppStart
    class DropletNotFound < StandardError; end
    class InvalidApp < StandardError; end

    def initialize(user, user_email, runners)
      @user = user
      @user_email = user_email
      @logger = Steno.logger('cc.action.app_start')
      @runners = runners
    end

    def start(app)
      raise DropletNotFound if !app.droplet

      app.db.transaction do
        app.lock!
        app.update(desired_state: 'STARTED')

        Repositories::Runtime::AppEventRepository.new.record_app_start(
          app,
          @user.guid,
          @user_email
        )
      end

      @runners.runner_for_app(app).start

    rescue Sequel::ValidationFailed => e
      raise InvalidApp.new(e.message)
    end
  end
end
