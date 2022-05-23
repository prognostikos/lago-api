# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plan, type: :model do
  describe '.has_trial?' do
    let(:plan) { create(:plan, trial_period: 3) }

    it 'returns true when trial_period' do
      expect(plan).to have_trial
    end
  end

  describe '.yearly_amount' do
    let(:plan) do
      build(:plan, interval: :yearly, amount: 100.00)
    end

    it { expect(plan.yearly_amount).to eq(100) }

    context 'when plan is monthly' do
      before { plan.interval = 'monthly' }

      it { expect(plan.yearly_amount).to eq(1200) }
    end

    context 'when plan is weekly' do
      before { plan.interval = 'weekly' }

      it { expect(plan.yearly_amount).to eq(5200) }
    end
  end
end
