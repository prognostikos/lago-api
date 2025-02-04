# frozen_string_literal: true

module Customers
  class UpdateService < BaseService
    def update(**args)
      customer = result.user.customers.find_by(id: args[:id])
      return result.fail!(code: 'not_found') unless customer

      customer.name = args[:name] if args.key?(:name)
      customer.country = args[:country]&.upcase if args.key?(:country)
      customer.address_line1 = args[:address_line1] if args.key?(:address_line1)
      customer.address_line2 = args[:address_line2] if args.key?(:address_line2)
      customer.state = args[:state] if args.key?(:state)
      customer.zipcode = args[:zipcode] if args.key?(:zipcode)
      customer.email = args[:email] if args.key?(:email)
      customer.city = args[:city] if args.key?(:city)
      customer.url = args[:url] if args.key?(:url)
      customer.phone = args[:phone] if args.key?(:phone)
      customer.logo_url = args[:logo_url] if args.key?(:logo_url)
      customer.legal_name = args[:legal_name] if args.key?(:legal_name)
      customer.legal_number = args[:legal_number] if args.key?(:legal_number)
      customer.vat_rate = args[:vat_rate] if args.key?(:vat_rate)
      customer.payment_provider = args[:payment_provider] if args.key?(:payment_provider)

      # NOTE: Customer_id is not editable if customer is attached to subscriptions
      if !customer.attached_to_subscriptions? && args.key?(:customer_id)
        customer.customer_id = args[:customer_id]
      end

      customer.save!

      # NOTE: if payment provider is updated, we need to create/update the provider customer
      create_or_update_provider_customer(customer, args[:stripe_customer])

      result.customer = customer
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    def create_or_update_provider_customer(customer, billing_configuration = {})
      handle_stripe_customer = customer.payment_provider.present?
      handle_stripe_customer ||= (billing_configuration || {})[:provider_customer_id].present?
      handle_stripe_customer ||= customer.stripe_customer&.provider_customer_id.present?
      return unless handle_stripe_customer

      create_result = PaymentProviderCustomers::CreateService.new(customer).create_or_update(
        customer_class: PaymentProviderCustomers::StripeCustomer,
        payment_provider_id: customer.organization.stripe_payment_provider&.id,
        params: billing_configuration,
      )
      create_result.throw_error unless create_result.success?
    end
  end
end
