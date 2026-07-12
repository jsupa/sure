require "test_helper"

class AccountTest < ActiveSupport::TestCase
  include SyncableInterfaceTest, EntriesTestHelper

  setup do
    @account = @syncable = accounts(:depository)
    @family = families(:dylan_family)
  end

  test "can destroy" do
    assert_difference "Account.count", -1 do
      @account.destroy
    end
  end

  test "gets short/long subtype label" do
    investment = Investment.new(subtype: "hsa")
    account = @family.accounts.create!(
      name: "Test Investment",
      balance: 1000,
      currency: "USD",
      accountable: investment
    )

    assert_equal "HSA", account.short_subtype_label
    assert_equal "Health Savings Account", account.long_subtype_label

    # Test with nil subtype
    account.accountable.update!(subtype: nil)
    assert_equal "Investments", account.short_subtype_label
    assert_equal "Investments", account.long_subtype_label
  end

  test "has account currency changes association" do
    assert_respond_to @account, :account_currency_changes
    assert_equal 0, @account.account_currency_changes.count
  end

  test "convert_currency delegates to CurrencyConverter" do
    # Mock the converter
    mock_converter = OpenStruct.new(call: OpenStruct.new(success?: true))
    Account::CurrencyConverter.expects(:new).with(
      account: @account,
      new_currency: "EUR"
    ).returns(mock_converter)
    
    result = @account.convert_currency("EUR")
    assert result.success?
  end

  test "currency_recently_changed? detects recent changes" do
    assert_not @account.currency_recently_changed?
    
    @account.account_currency_changes.create!(
      from_currency: "USD",
      to_currency: "EUR", 
      exchange_rate: 0.85,
      conversion_date: 1.day.ago
    )
    
    assert @account.currency_recently_changed?
  end

  test "latest_currency_change returns most recent change" do
    older_change = @account.account_currency_changes.create!(
      from_currency: "USD",
      to_currency: "EUR",
      exchange_rate: 0.85,
      conversion_date: 2.days.ago
    )
    
    newer_change = @account.account_currency_changes.create!(
      from_currency: "EUR",
      to_currency: "GBP",
      exchange_rate: 0.86,
      conversion_date: 1.day.ago
    )
    
    assert_equal newer_change, @account.latest_currency_change
  end
end
