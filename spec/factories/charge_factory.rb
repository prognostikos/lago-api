# frozen_string_literal: true

FactoryBot.define do
  factory :charge do
    billable_metric
    plan

    amount_currency { 'EUR' }

    factory :standard_charge do
      charge_model { 'standard' }
      properties do
        { amount: Faker::Number.decimal(l_digits: 3, r_digits: 3) }
      end
    end

    factory :graduated_charge do
      charge_model { 'graduated' }
      properties { [] }
    end

    factory :package_charge do
      charge_model { 'package' }
      properties do
        {
          amount: 100,
          free_units: 10,
          package_size: 10,
        }
      end
    end
  end
end
