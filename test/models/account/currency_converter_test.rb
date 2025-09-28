require "test_helper"

class Account::CurrencyConverterTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:depository)
    @family = families(:dylan_family)
    
    # Create exchange rate for testing
    @exchange_rate = ExchangeRate.create!(
      from_currency: "USD",
      to_currency: "EUR", 
      rate: 0.85,
      date: Date.current
    )
  end

  test "successfully converts account currency" do
    original_balance = @account.balance
    original_currency = @account.currency
    
    converter = Account::CurrencyConverter.new(
      account: @account,
      new_currency: "EUR"
    )
    
    result = converter.call
    
    assert result.success?
    assert_equal "EUR", @account.reload.currency
    assert_equal (original_balance * 0.85).round(4), @account.balance.round(4)
    
    # Check currency change record was created
    currency_change = @account.account_currency_changes.last
    assert_not_nil currency_change
    assert_equal "USD", currency_change.from_currency
    assert_equal "EUR", currency_change.to_currency
    assert_equal 0.85, currency_change.exchange_rate
  end

  test "fails when converting to same currency" do
    converter = Account::CurrencyConverter.new(
      account: @account,
      new_currency: @account.currency
    )
    
    result = converter.call
    
    assert_not result.success?
    assert_includes result.error, "already USD"
  end

  test "fails when converting to invalid currency" do
    converter = Account::CurrencyConverter.new(
      account: @account,
      new_currency: "INVALID"
    )
    
    result = converter.call
    
    assert_not result.success?
    assert_includes result.error, "Invalid currency"
  end

  test "fails when exchange rate not available" do
    converter = Account::CurrencyConverter.new(
      account: @account,
      new_currency: "JPY"  # No exchange rate set up
    )
    
    result = converter.call
    
    assert_not result.success?
    assert_includes result.error, "Exchange rate not available"
  end

  test "converts entries when use_historical_rates is true" do
    # Create an entry
    entry = @account.entries.create!(
      name: "Test Entry",
      amount: 100,
      currency: "USD",
      date: Date.current,
      entryable: Transaction.new
    )
    
    converter = Account::CurrencyConverter.new(
      account: @account,
      new_currency: "EUR",
      use_historical_rates: true
    )
    
    result = converter.call
    
    assert result.success?
    entry.reload
    assert_equal "EUR", entry.currency
    assert_equal 85.0, entry.amount  # 100 * 0.85
  end

  test "converts holdings currency and amounts" do
    # Create a holding
    security = Security.create!(name: "Test Stock", ticker: "TEST")
    holding = @account.holdings.create!(
      security: security,
      qty: 10,
      price: 50,
      amount: 500,
      currency: "USD",
      date: Date.current
    )
    
    converter = Account::CurrencyConverter.new(
      account: @account,
      new_currency: "EUR"
    )
    
    result = converter.call
    
    assert result.success?
    holding.reload
    assert_equal "EUR", holding.currency
    assert_equal 10, holding.qty  # Quantity stays the same
    assert_equal 42.5, holding.price  # 50 * 0.85
    assert_equal 425.0, holding.amount  # 500 * 0.85
  end
end