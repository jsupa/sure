class Account::CurrencyConverter
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :account
  attribute :new_currency, :string
  attribute :conversion_date, :date, default: -> { Date.current }
  attribute :use_historical_rates, :boolean, default: true

  validates :account, :new_currency, :conversion_date, presence: true
  
  def call
    return OpenStruct.new(success?: false, error: "Account currency is already #{new_currency}") if account.currency == new_currency
    return OpenStruct.new(success?: false, error: "Invalid currency") unless valid_currency?

    ActiveRecord::Base.transaction do
      exchange_rate = get_exchange_rate
      return OpenStruct.new(success?: false, error: "Exchange rate not available") unless exchange_rate

      # Record the currency change
      currency_change = create_currency_change_record(exchange_rate)
      
      # Convert account balance and cash balance
      convert_account_balances(exchange_rate)
      
      # Convert all entries (transactions, trades, valuations)
      convert_entries(exchange_rate) if use_historical_rates
      
      # Convert all balances
      convert_balances(exchange_rate) if use_historical_rates
      
      # Convert holdings
      convert_holdings(exchange_rate) if use_historical_rates
      
      # Update account currency
      account.update!(currency: new_currency)
      
      # Trigger account sync to recalculate everything
      account.sync_later

      OpenStruct.new(
        success?: true, 
        currency_change: currency_change,
        exchange_rate: exchange_rate,
        message: "Currency converted from #{currency_change.from_currency} to #{new_currency}"
      )
    end
  rescue => e
    Rails.logger.error "Currency conversion error: #{e.message}"
    OpenStruct.new(success?: false, error: e.message)
  end

  private

  def valid_currency?
    Money::Currency.new(new_currency)
    true
  rescue Money::Currency::UnknownCurrencyError
    false
  end

  def get_exchange_rate
    # Try to get exchange rate for the conversion date
    rate_record = ExchangeRate.find_by(
      from_currency: account.currency,
      to_currency: new_currency,
      date: conversion_date
    )
    
    return rate_record.rate if rate_record

    # Try to get the most recent rate if specific date not available
    recent_rate = ExchangeRate.where(
      from_currency: account.currency,
      to_currency: new_currency
    ).order(date: :desc).first

    return recent_rate.rate if recent_rate

    # If no rate found, try to fetch it
    begin
      fetched_rate = ExchangeRate.find_or_fetch_rate(
        from: account.currency,
        to: new_currency,
        date: conversion_date
      )
      fetched_rate&.rate
    rescue => e
      Rails.logger.warn "Could not fetch exchange rate: #{e.message}"
      nil
    end
  end

  def create_currency_change_record(exchange_rate)
    account.account_currency_changes.create!(
      from_currency: account.currency,
      to_currency: new_currency,
      exchange_rate: exchange_rate,
      conversion_date: conversion_date,
      notes: "Automatic currency conversion"
    )
  end

  def convert_account_balances(exchange_rate)
    # Convert main balance
    if account.balance.present?
      new_balance = account.balance * exchange_rate
      account.update_column(:balance, new_balance)
    end

    # Convert cash balance
    if account.cash_balance.present?
      new_cash_balance = account.cash_balance * exchange_rate
      account.update_column(:cash_balance, new_cash_balance)
    end
  end

  def convert_entries(exchange_rate)
    account.entries.find_each do |entry|
      if use_historical_rates
        # Use historical rate for the entry date
        historical_rate = get_historical_rate_for_date(entry.date) || exchange_rate
        new_amount = entry.amount * historical_rate
      else
        new_amount = entry.amount * exchange_rate
      end

      entry.update_columns(
        amount: new_amount,
        currency: new_currency
      )
    end
  end

  def convert_balances(exchange_rate)
    account.balances.find_each do |balance|
      conversion_rate = if use_historical_rates
        get_historical_rate_for_date(balance.date) || exchange_rate
      else
        exchange_rate
      end

      # Convert all balance fields
      balance_fields = %w[
        balance cash_balance 
        start_cash_balance start_non_cash_balance
        cash_inflows cash_outflows non_cash_inflows non_cash_outflows
        net_market_flows cash_adjustments non_cash_adjustments
      ]

      updates = { currency: new_currency }
      balance_fields.each do |field|
        if balance.send(field).present?
          updates[field] = balance.send(field) * conversion_rate
        end
      end

      balance.update_columns(updates)
    end
  end

  def convert_holdings(exchange_rate)
    account.holdings.find_each do |holding|
      conversion_rate = if use_historical_rates
        get_historical_rate_for_date(holding.date) || exchange_rate
      else
        exchange_rate
      end

      # Convert price and amount, keep qty the same
      new_price = holding.price * conversion_rate if holding.price.present?
      new_amount = holding.amount * conversion_rate if holding.amount.present?

      holding.update_columns(
        price: new_price,
        amount: new_amount,
        currency: new_currency
      )
    end
  end

  def get_historical_rate_for_date(date)
    return nil unless use_historical_rates

    rate_record = ExchangeRate.find_by(
      from_currency: account.currency,
      to_currency: new_currency,
      date: date
    )
    
    rate_record&.rate
  end
end