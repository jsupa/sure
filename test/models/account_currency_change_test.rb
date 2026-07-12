require "test_helper"

class AccountCurrencyChangeTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:depository)
    @currency_change = AccountCurrencyChange.create!(
      account: @account,
      from_currency: "USD",
      to_currency: "EUR",
      exchange_rate: 0.85,
      conversion_date: Date.current
    )
  end

  test "belongs to account" do
    assert_equal @account, @currency_change.account
  end

  test "validates required fields" do
    change = AccountCurrencyChange.new
    assert_not change.valid?
    
    %i[from_currency to_currency exchange_rate conversion_date].each do |field|
      assert_includes change.errors[field], "can't be blank"
    end
  end

  test "validates exchange rate is positive" do
    change = AccountCurrencyChange.new(
      account: @account,
      from_currency: "USD",
      to_currency: "EUR",
      exchange_rate: -0.5,
      conversion_date: Date.current
    )
    
    assert_not change.valid?
    assert_includes change.errors[:exchange_rate], "must be greater than 0"
  end

  test "formatted_exchange_rate returns proper format" do
    expected = "1 USD = 0.85 EUR"
    assert_equal expected, @currency_change.formatted_exchange_rate
  end

  test "conversion_summary includes date and currencies" do
    summary = @currency_change.conversion_summary
    assert_includes summary, "USD → EUR"
    assert_includes summary, "0.85"
    assert_includes summary, Date.current.to_s
  end

  test "chronological scope orders by date and created_at" do
    older_change = AccountCurrencyChange.create!(
      account: @account,
      from_currency: "EUR",
      to_currency: "GBP",
      exchange_rate: 0.86,
      conversion_date: 1.day.ago
    )
    
    changes = AccountCurrencyChange.chronological
    assert_equal older_change, changes.first
    assert_equal @currency_change, changes.last
  end

  test "recent scope orders by created_at desc" do
    older_change = AccountCurrencyChange.create!(
      account: @account,
      from_currency: "EUR",
      to_currency: "GBP",
      exchange_rate: 0.86,
      conversion_date: Date.current
    )
    
    changes = AccountCurrencyChange.recent
    assert_equal older_change, changes.first
    assert_equal @currency_change, changes.last
  end
end