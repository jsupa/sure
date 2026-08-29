require "test_helper"

class FinancialSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    @account = accounts(:depository)
    @subscription = FinancialSubscription.create!(
      family: @family,
      account: @account,
      name: "Netflix",
      amount: 15.99,
      currency: "USD",
      recurrence: "monthly",
      next_payment_date: Date.current + 1.week
    )
  end

  test "should get index" do
    get financial_subscriptions_url
    assert_response :success
    assert_includes response.body, "Subscriptions"
    assert_includes response.body, @subscription.name
  end

  test "index shows overdue subscriptions separately" do
    overdue_subscription = FinancialSubscription.create!(
      family: @family,
      account: @account,
      name: "Overdue Subscription",
      amount: 10,
      currency: "USD",
      recurrence: "monthly",
      next_payment_date: Date.current - 1.day
    )

    get financial_subscriptions_url
    assert_response :success
    assert_includes response.body, "Overdue Subscriptions"
    assert_includes response.body, overdue_subscription.name
  end

  test "should create financial_subscription" do
    assert_difference("FinancialSubscription.count") do
      post financial_subscriptions_url, params: {
        financial_subscription: {
          name: "Spotify",
          account_id: @account.id,
          amount: 9.99,
          currency: "USD",
          recurrence: "monthly",
          next_payment_date: Date.current + 1.month,
          description: "Music streaming"
        }
      }
    end

    assert_redirected_to financial_subscriptions_path
    follow_redirect!
    assert_includes response.body, "Subscription was successfully created"
  end

  test "should not create financial_subscription with invalid params" do
    assert_no_difference("FinancialSubscription.count") do
      post financial_subscriptions_url, params: {
        financial_subscription: {
          name: "", # Invalid: empty name
          account_id: @account.id,
          amount: 9.99,
          currency: "USD",
          recurrence: "monthly",
          next_payment_date: Date.current + 1.month
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "should not update financial_subscription with invalid params" do
    original_name = @subscription.name

    patch financial_subscription_url(@subscription), params: {
      financial_subscription: {
        name: "", # Invalid
        amount: -10 # Invalid
      }
    }

    assert_response :unprocessable_entity
    @subscription.reload
    assert_equal original_name, @subscription.name
  end

  test "should destroy financial_subscription" do
    assert_difference("FinancialSubscription.count", -1) do
      delete financial_subscription_url(@subscription)
    end

    assert_redirected_to financial_subscriptions_path
    follow_redirect!
    assert_includes response.body, "Subscription was successfully deleted"
  end

  test "should mark subscription as paid" do
    overdue_subscription = FinancialSubscription.create!(
      family: @family,
      account: @account,
      name: "Overdue Subscription",
      amount: 10,
      currency: "USD",
      recurrence: "monthly",
      next_payment_date: Date.current - 1.day
    )

    original_next_payment_date = overdue_subscription.next_payment_date

    assert_difference([ "FinancialSubscriptionPayment.count", "Transaction.count" ]) do
      patch mark_as_paid_financial_subscription_url(overdue_subscription)
    end

    assert_redirected_to financial_subscriptions_path
    follow_redirect!
    assert_includes response.body, "Payment recorded successfully"

    overdue_subscription.reload
    assert overdue_subscription.next_payment_date > original_next_payment_date
  end

  test "only shows subscriptions for current family" do
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
      name: "Other Family Subscription",
      amount: 25,
      currency: "USD",
      recurrence: "monthly",
      next_payment_date: Date.current
    )

    get financial_subscriptions_url
    assert_response :success

    assert_includes response.body, @subscription.name
    assert_not_includes response.body, other_subscription.name
  end
end
