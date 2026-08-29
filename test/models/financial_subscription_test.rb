require "test_helper"

class FinancialSubscriptionTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    @subscription = FinancialSubscription.new(
      family: @family,
      account: @account,
      name: "Netflix",
      amount: 15.99,
      currency: "USD",
      recurrence: "monthly",
      next_payment_date: Date.current + 1.week
    )
  end

  test "should be valid with valid attributes" do
    assert @subscription.valid?
  end

  test "should require name" do
    @subscription.name = nil
    assert_not @subscription.valid?
    assert_includes @subscription.errors[:name], "can't be blank"
  end

  test "should require amount" do
    @subscription.amount = nil
    assert_not @subscription.valid?
    assert_includes @subscription.errors[:amount], "can't be blank"
  end

  test "should require positive amount" do
    @subscription.amount = -10
    assert_not @subscription.valid?
    assert_includes @subscription.errors[:amount], "must be greater than 0"
  end

  test "should require currency" do
    @subscription.currency = nil
    assert_not @subscription.valid?
    assert_includes @subscription.errors[:currency], "can't be blank"
  end

  test "should require recurrence" do
    @subscription.recurrence = nil
    assert_not @subscription.valid?
    assert_includes @subscription.errors[:recurrence], "can't be blank"
  end

  test "should require next_payment_date" do
    @subscription.next_payment_date = nil
    assert_not @subscription.valid?
    assert_includes @subscription.errors[:next_payment_date], "can't be blank"
  end

  test "overdue? returns true when next_payment_date is in the past" do
    @subscription.next_payment_date = Date.current - 1.day
    assert @subscription.overdue?
  end

  test "overdue? returns false when next_payment_date is in the future" do
    @subscription.next_payment_date = Date.current + 1.day
    assert_not @subscription.overdue?
  end

  test "days_overdue returns correct number of days" do
    @subscription.next_payment_date = Date.current - 5.days
    assert_equal 5, @subscription.days_overdue
  end

  test "days_overdue returns 0 when not overdue" do
    @subscription.next_payment_date = Date.current + 1.day
    assert_equal 0, @subscription.days_overdue
  end

  test "calculate_next_payment_date for monthly recurrence" do
    date = Date.parse("2024-01-15")
    @subscription.recurrence = "monthly"
    expected = Date.parse("2024-02-15")
    assert_equal expected, @subscription.calculate_next_payment_date(date)
  end

  test "calculate_next_payment_date for yearly recurrence" do
    date = Date.parse("2024-01-15")
    @subscription.recurrence = "yearly"
    expected = Date.parse("2025-01-15")
    assert_equal expected, @subscription.calculate_next_payment_date(date)
  end

  test "calculate_next_payment_date for weekly recurrence" do
    date = Date.parse("2024-01-15")
    @subscription.recurrence = "weekly"
    expected = Date.parse("2024-01-22")
    assert_equal expected, @subscription.calculate_next_payment_date(date)
  end

  test "calculate_next_payment_date for daily recurrence" do
    date = Date.parse("2024-01-15")
    @subscription.recurrence = "daily"
    expected = Date.parse("2024-01-16")
    assert_equal expected, @subscription.calculate_next_payment_date(date)
  end

  test "calculate_next_payment_date for quarterly recurrence" do
    date = Date.parse("2024-01-15")
    @subscription.recurrence = "quarterly"
    expected = Date.parse("2024-04-15")
    assert_equal expected, @subscription.calculate_next_payment_date(date)
  end

  test "scopes work correctly" do
    overdue_subscription = FinancialSubscription.create!(
      family: @family,
      account: @account,
      name: "Overdue Subscription",
      amount: 10,
      currency: "USD",
      recurrence: "monthly",
      next_payment_date: Date.current - 1.day
    )

    upcoming_subscription = FinancialSubscription.create!(
      family: @family,
      account: @account,
      name: "Upcoming Subscription",
      amount: 20,
      currency: "USD",
      recurrence: "monthly",
      next_payment_date: Date.current + 3.days
    )

    assert_includes FinancialSubscription.overdue, overdue_subscription
    assert_not_includes FinancialSubscription.overdue, upcoming_subscription

    assert_includes FinancialSubscription.upcoming(7), upcoming_subscription
    assert_not_includes FinancialSubscription.upcoming(7), overdue_subscription

    assert_includes FinancialSubscription.for_family(@family), overdue_subscription
    assert_includes FinancialSubscription.for_family(@family), upcoming_subscription
  end
end
