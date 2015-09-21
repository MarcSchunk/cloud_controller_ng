require 'messages/validators'

module VCAP::CloudController
  class DropletsListMessage
    include ActiveModel::Model
    include VCAP::CloudController::Validators

    VALID_ORDER_BY_KEYS = /created_at|updated_at/

    attr_accessor :app_guids, :states, :page, :per_page, :order_by

    validates :app_guids, array: true, allow_blank: true
    validates :states, array: true, allow_blank: true
    validates_numericality_of :page, greater_than: 0, allow_blank: true
    validates_numericality_of :per_page, greater_than: 0, allow_blank: true
    validates_format_of :order_by, with: /[+-]?(#{VALID_ORDER_BY_KEYS})/, allow_blank: true
  end
end
