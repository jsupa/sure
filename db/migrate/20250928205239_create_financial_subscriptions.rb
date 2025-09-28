class CreateFinancialSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :financial_subscriptions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :currency, null: false
      t.string :recurrence, null: false
      t.date :next_payment_date, null: false
      t.text :description
      t.timestamps

      t.index [:family_id, :name], unique: true
      t.index :next_payment_date
      t.index :recurrence
    end
  end
end
