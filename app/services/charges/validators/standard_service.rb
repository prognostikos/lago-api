# frozen_string_literal: true

module Charges
  module Validators
    class StandardService < Charges::Validators::BaseService
      def validate
        errors = []
        errors << :invalid_amount unless valid_amount?

        return result.fail!(:invalid_properties, errors) if errors.present?

        result
      end

      private

      def amount
        BigDecimal(properties['amount'])
      end

      def valid_amount?
        amount.present? && amount.finite? && amount.positive?
      end
    end
  end
end
