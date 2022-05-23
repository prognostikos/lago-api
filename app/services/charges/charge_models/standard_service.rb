# frozen_string_literal: true

module Charges
  module ChargeModels
    class StandardService < Charges::ChargeModels::BaseService
      def apply(value:)
        result.amount = (value * BigDecimal(charge.properties['amount']))
        result
      end
    end
  end
end
