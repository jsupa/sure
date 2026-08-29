require "test_helper"

class FinancialSubscriptionPaymentTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)

    @subscription = FinancialSubscription.create!(
      account: @account,
      family: @family,
      name: "Test Subscription",
      amount: 19.99,
      currency: "USD",
      recurrence: "monthly",
      next_payment_date: Date.current
    )

    @entry = Entry.create!(
      account: @account,
      entryable: Transaction.new,
      name: "Test Transaction",
      date: Date.current,
      amount: -19.99,
      currency: "USD"
    )
    @transaction = @entry.entryable

    @payment = FinancialSubscriptionPayment.create!(
      financial_subscription: @subscription,
      amount: 19.99,
      currency: "USD",
      payment_date: Date.current,
      transaction_id: @transaction.id
    )
  end

  test "should be valid with valid attributes" do
    assert @payment.valid?
  end

  test "should require payment_date" do
    @payment.payment_date = nil
    assert_not @payment.valid?
    assert_includes @payment.errors[:payment_date], "can't be blank"
  end

  test "should require amount" do
    @payment.amount = nil
    assert_not @payment.valid?
    assert_includes @payment.errors[:amount], "can't be blank"
  end

  test "should require positive amount" do
    @payment.amount = -10
    assert_not @payment.valid?
    assert_includes @payment.errors[:amount], "must be greater than 0"
  end

  test "should require currency" do
    @payment.currency = nil
    assert_not @payment.valid?
    assert_includes @payment.errors[:currency], "can't be blank"
  end

  test "should belong to financial subscription" do
    assert_equal @subscription, @payment.financial_subscription
  end

  test "should belong to transaction" do
    assert_equal @transaction, @payment.payment_transaction
    assert_equal @transaction, @payment.transaction # Test alias
  end

  test "delegates work correctly" do
    @payment.save!
    assert_equal @subscription.account, @payment.subscription_account
    assert_equal @subscription.family, @payment.subscription_family
    assert_equal @subscription.name, @payment.subscription_name
  end

  test "recent scope orders by payment_date desc" do
    old_entry = Entry.create!(
      account: @account,
      entryable: Transaction.new,
      name: "Old Transaction",
      date: Date.current - 2.days,
      amount: -15.99,
      currency: "USD"
    )
    old_transaction = old_entry.entryable

    new_entry = Entry.create!(
      account: @account,
      entryable: Transaction.new,
      name: "New Transaction",
      date: Date.current + 1.day,
      amount: -20.99,
      currency: "USD"
    )
    new_transaction = new_entry.entryable

    old_payment = FinancialSubscriptionPayment.create!(
      financial_subscription: @subscription,
      transaction_id: old_transaction.id,
      payment_date: Date.current - 2.days,
      amount: 15.99,
      currency: "USD"
    )

    new_payment = FinancialSubscriptionPayment.create!(
      financial_subscription: @subscription,
      transaction_id: new_transaction.id,
      payment_date: Date.current + 1.day,
      amount: 20.99,
      currency: "USD"
    )

    # Get only the payments we created for this test
    test_payments = [ old_payment, new_payment ].sort_by(&:payment_date).reverse

    assert_equal new_payment, test_payments.first
    assert_equal old_payment, test_payments.second

    # Also test that the recent scope orders correctly
    recent_payments = FinancialSubscriptionPayment.recent
    newest_payment = recent_payments.find { |p| p.payment_date == (Date.current + 1.day) }
    oldest_payment = recent_payments.find { |p| p.payment_date == (Date.current - 2.days) }

    assert newest_payment.present?
    assert oldest_payment.present?
    assert recent_payments.index(newest_payment) < recent_payments.index(oldest_payment)
  end

  test "for_family scope filters correctly" do
    other_family = Family.create!(name: "Other Family")
    other_account = Account.create!(
      family: other_family,
      name: "Other Account",
      balance: 1000,
      currency: "USD",
      accountable: Depository.new
    )
    other_subscription = FinancialSubscription.create!(
      family: other_family,
      account: other_account,
      name: "Other Subscription",
      amount: 10,
      currency: "USD",
      recurrence: "monthly",
      next_payment_date: Date.current
    )
    other_payment = FinancialSubscriptionPayment.create!(
      financial_subscription: other_subscription,
      transaction_id: @transaction.id,
      payment_date: Date.current,
      amount: 10,
      currency: "USD"
    )

    @payment.save!

    family_payments = FinancialSubscriptionPayment.for_family(@family)
    assert_includes family_payments, @payment
    assert_not_includes family_payments, other_payment
  end
end
