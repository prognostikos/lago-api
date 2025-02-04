# frozen_string_literal: true

module Resolvers
  class WalletsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query wallets'

    argument :ids, [ID], required: false, description: 'List of wallet IDs to fetch'
    argument :customer_id, ID, required: true, description: 'Uniq ID of the customer'
    argument :page, Integer, required: false
    argument :limit, Integer, required: false
    argument :status, Types::Wallets::StatusEnum, required: false

    type Types::Wallets::Object.collection_type, null: false

    def resolve(customer_id: nil, ids: nil, page: nil, limit: nil, status: nil)
      validate_organization!

      current_customer = Customer.find(customer_id)

      wallets = current_customer
        .wallets
        .page(page)
        .limit(limit)

      wallets = wallets.where(status: status) if status.present?
      wallets = wallets.where(id: ids) if ids.present?

      wallets
    rescue ActiveRecord::RecordNotFound
      not_found_error
    end
  end
end
