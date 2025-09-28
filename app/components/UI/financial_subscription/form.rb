class UI::FinancialSubscription::Form < ApplicationComponent
  attr_reader :subscription, :accounts

  def initialize(subscription:, accounts:)
    @subscription = subscription
    @accounts = accounts
  end

  def recurrence_options
    FinancialSubscription.recurrences.map do |key, _|
      [key.humanize, key]
    end
  end

  def currency_options
    # Get unique currencies from user's accounts
    currencies = accounts.map(&:currency).uniq.sort
    currencies.map { |currency| [currency, currency] }
  end
end