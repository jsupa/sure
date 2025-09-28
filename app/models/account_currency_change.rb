class AccountCurrencyChange < ApplicationRecord
  belongs_to :account

  validates :from_currency, :to_currency, :exchange_rate, :conversion_date, presence: true
  validates :exchange_rate, numericality: { greater_than: 0 }

  scope :chronological, -> { order(:conversion_date, :created_at) }
  scope :recent, -> { order(created_at: :desc) }

  def formatted_exchange_rate
    "1 #{from_currency} = #{exchange_rate} #{to_currency}"
  end

  def conversion_summary
    "#{from_currency} → #{to_currency} (#{formatted_exchange_rate}) on #{I18n.l(conversion_date)}"
  end
end