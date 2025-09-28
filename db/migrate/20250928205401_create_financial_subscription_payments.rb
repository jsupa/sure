class CreateFinancialSubscriptionPayments < ActiveRecord::Migration[7.2]
  def change
    create_table :financial_subscription_payments, id: :uuid do |t|
      t.references :financial_subscription, null: false, foreign_key: true, type: :uuid
      t.references :transaction, null: false, foreign_key: true, type: :uuid
      t.date :payment_date, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :currency, null: false
      t.timestamps

      t.index [ :financial_subscription_id, :payment_date ], name: 'index_fin_sub_payments_on_subscription_and_date'
      t.index :payment_date
    end
  end
end
