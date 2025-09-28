class CreateAccountCurrencyChanges < ActiveRecord::Migration[7.2]
  def change
    create_table :account_currency_changes, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.string :from_currency, null: false
      t.string :to_currency, null: false
      t.decimal :exchange_rate, precision: 19, scale: 8
      t.date :conversion_date, null: false
      t.text :notes
      t.timestamps
    end

    add_index :account_currency_changes, [:account_id, :conversion_date]
    add_index :account_currency_changes, [:from_currency, :to_currency]
  end
end
