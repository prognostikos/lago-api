# frozen_string_literal: true

FactoryBot.define do
  factory :fee do
    invoice
    charge { nil }
    subscription

    amount { 200.00 }
    amount_currency { 'EUR' }

    vat_amount { 2.00 }
    vat_amount_currency { 'EUR' }
  end
end
