# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::CreateService, type: :service do
  subject(:create_service) { described_class.new }

  let(:organization) { create(:organization) }

  describe '.create_from_api' do
    let(:plan) { create(:plan, amount_cents: 100, organization: organization) }
    let(:customer) { create(:customer, organization: organization) }
    let(:unique_id) { SecureRandom.uuid }

    let(:params) do
      {
        customer_id: customer.customer_id,
        plan_code: plan.code,
        name: 'invoice display name',
        unique_id: unique_id,
      }
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates a subscription' do
      result = create_service.create_from_api(
        organization: organization,
        params: params,
      )

      expect(result).to be_success

      subscription = result.subscription

      aggregate_failures do
        expect(subscription.customer_id).to eq(customer.id)
        expect(subscription.plan_id).to eq(plan.id)
        expect(subscription.started_at).to be_present
        expect(subscription.subscription_date).to be_present
        expect(subscription.name).to eq('invoice display name')
        expect(subscription).to be_active
      end
    end

    it 'calls SegmentTrackJob' do
      subscription = create_service.create_from_api(
        organization: organization,
        params: params,
      ).subscription

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'subscription_created',
        properties: {
          created_at: subscription.created_at,
          customer_id: subscription.customer_id,
          plan_code: subscription.plan.code,
          plan_name: subscription.plan.name,
          subscription_type: 'create',
          organization_id: subscription.organization.id
        }
      )
    end

    context 'when customer does not exists' do
      let(:params) do
        {
          customer_id: SecureRandom.uuid,
          plan_code: plan.code,
          unique_id: unique_id,
        }
      end

      it 'creates a customer' do
        result = create_service.create_from_api(
          organization: organization,
          params: params,
        )

        expect(result).to be_success

        subscription = result.subscription

        aggregate_failures do
          expect(subscription.customer.customer_id).to eq(params[:customer_id])
          expect(subscription.plan_id).to eq(plan.id)
          expect(subscription.started_at).to be_present
          expect(subscription.subscription_date).to be_present
          expect(subscription).to be_active
        end
      end

      context 'when plan is pay_in_advance' do
        before { plan.update(pay_in_advance: true) }

        it 'enqueued a job to bill the subscription' do
          expect do
            create_service.create_from_api(
              organization: organization,
              params: params,
            )
          end.to have_enqueued_job(BillSubscriptionJob)
        end
      end
    end

    context 'when customer id is missing' do
      let(:params) do
        {
          customer_id: nil,
          plan_code: plan.code,
          unique_id: unique_id,
        }
      end

      it 'fails' do
        result = create_service.create_from_api(
          organization: organization,
          params: params,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('unable to find customer')
      end
    end

    context 'when plan doest not exists' do
      let(:params) do
        {
          customer_id: customer.customer_id,
          plan_code: 'invalid_plan',
          unique_id: unique_id,
        }
      end

      it 'fails' do
        result = create_service.create_from_api(
          organization: organization,
          params: params,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('plan does not exists')
      end
    end

    context 'when an active subscription already exists' do
      let(:params) do
        {
          customer_id: customer.customer_id,
          plan_code: plan.code,
          name: 'invoice display name',
          subscription_id: subscription.id,
          unique_id: unique_id,
        }
      end
      let(:subscription) do
        create(
          :subscription,
          customer: customer,
          plan: plan,
          status: :active,
          subscription_date: Time.zone.now.to_date,
          started_at: Time.zone.now,
        )
      end

      before { subscription }

      context 'when new plan has different currency than the old plan' do
        let(:new_plan) { create(:plan, amount_cents: 200, organization: organization, amount_currency: 'USD') }
        let(:params) do
          {
            customer_id: customer.customer_id,
            plan_code: new_plan.code,
            name: 'invoice display name new',
            unique_id: unique_id,
          }
        end

        it 'fails' do
          result = create_service.create_from_api(
            organization: organization,
            params: params,
            )

          expect(result).not_to be_success
          expect(result.error).to eq('currencies does not match')
        end
      end

      context 'when plan is the same and unique id is different' do
        it 'returns new subscription' do
          result = create_service.create_from_api(
            organization: organization,
            params: params,
          )

          expect(result).to be_success
          expect(result.subscription.id).not_to eq(subscription.id)
        end
      end

      context 'when plan is the same and unique id is the same' do
        before do
          subscription.update!(unique_id: unique_id)
        end

        it 'returns existing subscription' do
          result = create_service.create_from_api(
            organization: organization,
            params: params,
          )

          expect(result).to be_success
          expect(result.subscription.id).to eq(subscription.id)
        end
      end

      context 'when plan is not the same' do
        context 'when we upgrade the plan' do
          let(:higher_plan) { create(:plan, amount_cents: 200, organization: organization) }
          let(:params) do
            {
              customer_id: customer.customer_id,
              plan_code: higher_plan.code,
              name: 'invoice display name new',
              subscription_id: subscription.id,
              unique_id: unique_id,
            }
          end

          it 'terminates the existing subscription' do
            create_service.create_from_api(
              organization: organization,
              params: params,
            )

            old_subscription = Subscription.find(subscription.id)

            expect(old_subscription).to be_terminated
          end

          it 'creates a new subscription' do
            result = create_service.create_from_api(
              organization: organization,
              params: params,
            )

            aggregate_failures do
              expect(result).to be_success
              expect(result.subscription.id).not_to eq(subscription.id)
              expect(result.subscription).to be_active
              expect(result.subscription.name).to eq('invoice display name new')
              expect(result.subscription.plan.id).to eq(higher_plan.id)
              expect(result.subscription.previous_subscription_id).to eq(subscription.id)
              expect(result.subscription.subscription_date).to eq(subscription.subscription_date)
            end
          end

          context 'when old subscription is payed in arrear' do
            before { plan.update!(pay_in_advance: false) }

            it 'enqueues a job to bill the existing subscription' do
              expect do
                create_service.create_from_api(
                  organization: organization,
                  params: params,
                )
              end.to have_enqueued_job(BillSubscriptionJob)
            end
          end

          context 'when new subscription is payed in advance' do
            before { higher_plan.update!(pay_in_advance: false) }

            it 'enqueues a job to bill the existing subscription' do
              expect do
                create_service.create_from_api(
                  organization: organization,
                  params: params,
                )
              end.to have_enqueued_job(BillSubscriptionJob)
            end
          end

          context 'with pending next subscription' do
            let(:next_subscription) do
              create(
                :subscription,
                status: :pending,
                previous_subscription: subscription,
                organization: subscription.organization,
              )
            end

            before { next_subscription }

            it 'canceled the next subscription' do
              result = create_service.create_from_api(
                organization: organization,
                params: params,
              )

              aggregate_failures do
                expect(result).to be_success
                expect(next_subscription.reload).to be_canceled
              end
            end
          end
        end

        context 'when we downgrade the plan' do
          let(:lower_plan) do
            create(:plan, amount_cents: 50, organization: organization)
          end

          let(:params) do
            {
              customer_id: customer.customer_id,
              plan_code: lower_plan.code,
              name: 'invoice display name new',
              subscription_id: subscription.id,
              unique_id: unique_id,
            }
          end

          it 'creates a new subscription' do
            result = create_service.create_from_api(
              organization: organization,
              params: params,
            )

            aggregate_failures do
              expect(result).to be_success

              next_subscription = result.subscription.next_subscription
              expect(next_subscription.id).not_to eq(subscription.id)
              expect(next_subscription).to be_pending
              expect(next_subscription.name).to eq('invoice display name new')
              expect(next_subscription.plan_id).to eq(lower_plan.id)
              expect(next_subscription.subscription_date).to eq(subscription.subscription_date)
              expect(next_subscription.previous_subscription).to eq(subscription)
            end
          end

          it 'keeps the current subscription' do
            result = create_service.create_from_api(
              organization: organization,
              params: params,
            )

            aggregate_failures do
              expect(result.subscription.id).to eq(subscription.id)
              expect(result.subscription).to be_active
              expect(result.subscription.next_subscription).to be_present
            end
          end

          context 'with pending next subscription' do
            let(:next_subscription) do
              create(
                :subscription,
                status: :pending,
                previous_subscription: subscription,
                organization: subscription.organization,
              )
            end

            before { next_subscription }

            it 'canceled the next subscription' do
              result = create_service.create_from_api(
                organization: organization,
                params: params,
              )

              aggregate_failures do
                expect(result).to be_success
                expect(next_subscription.reload).to be_canceled
              end
            end
          end
        end
      end
    end
  end

  describe '.create' do
    let(:plan) { create(:plan, amount_cents: 100, organization: organization) }
    let(:customer) { create(:customer, organization: organization) }

    let(:params) do
      {
        customer_id: customer.id,
        plan_id: plan.id,
        organization_id: organization.id,
      }
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates a subscription' do
      result = create_service.create(**params)

      expect(result).to be_success

      subscription = result.subscription

      aggregate_failures do
        expect(subscription.customer_id).to eq(customer.id)
        expect(subscription.plan_id).to eq(plan.id)
        expect(subscription.started_at).to be_present
        expect(subscription.subscription_date).to be_present
        expect(subscription).to be_active
      end
    end

    it 'calls SegmentTrackJob' do
      subscription = create_service.create(**params).subscription

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'subscription_created',
        properties: {
          created_at: subscription.created_at,
          customer_id: subscription.customer_id,
          plan_code: subscription.plan.code,
          plan_name: subscription.plan.name,
          subscription_type: 'create',
          organization_id: subscription.organization.id
        }
      )
    end

    context 'when customer does not exists' do
      let(:params) do
        {
          customer_id: SecureRandom.uuid,
          plan_code: plan.id,
          organization_id: organization.id,
        }
      end

      it 'fails' do
        result = create_service.create(**params)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to eq('unable to find customer')
        end
      end
    end

    context 'when plan doest not exists' do
      let(:params) do
        {
          customer_id: customer.id,
          plan_code: 'invalid_plan',
          organization_id: organization.id,
        }
      end

      it 'fails' do
        result = create_service.create(**params)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to eq('plan does not exists')
        end
      end
    end
  end
end
