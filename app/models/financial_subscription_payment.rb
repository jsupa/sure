class FinancialSubscriptionPayment < ApplicationRecord
  include Monetizable

  belongs_to :financial_subscription
  belongs_to :payment_transaction, class_name: "Transaction", foreign_key: "transaction_id", optional: true

  validates :payment_date, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true

  monetize :amount

  scope :recent, -> { order(payment_date: :desc) }
  scope :for_family, ->(family) { joins(:financial_subscription).where(financial_subscriptions: { family: family }) }

  delegate :account, :family, :name, to: :financial_subscription, prefix: :subscription

  # Alias for backward compatibility
  alias_method :transaction, :payment_transaction
end
