# frozen_string_literal: trues

class AddAmountOnAmountablesModels < ActiveRecord::Migration[7.0]
  def change
    add_column :plans, :amount, :numeric, precision: 15, scale: 10
    add_column :coupons, :amount, :numeric, precision: 15, scale: 10
    add_column :fees, :vat_amount, :numeric, precision: 15, scale: 10
    add_column :fees, :amount, :numeric, precision: 15, scale: 10
    add_column :invoices, :amount, :numeric, precision: 15, scale: 10
    add_column :invoices, :vat_amount, :numeric, precision: 15, scale: 10
    add_column :invoices, :total_amount, :numeric, precision: 15, scale: 10

    change_column_default :plans, :amount_cents, from: nil, to: 0
    change_column_default :coupons, :amount_cents, from: nil, to: 0
    change_column_default :fees, :amount_cents, from: nil, to: 0
    change_column_default :fees, :vat_amount_cents, from: nil, to: 0
    change_column_default :invoices, :amount_cents, from: nil, to: 0
    change_column_default :invoices, :vat_amount_cents, from: nil, to: 0
    change_column_default :invoices, :total_amount_cents, from: nil, to: 0
  end
end
