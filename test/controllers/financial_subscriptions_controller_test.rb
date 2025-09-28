require "test_helper"

class FinancialSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:dylan)
    @family = families(:dylan_family)
    @account = accounts(:dylan_checking)
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

  test "should show financial_subscription" do
    get financial_subscription_url(@subscription)
    assert_response :success
    assert_includes response.body, @subscription.name
  end

  test "should get edit" do
    get edit_financial_subscription_url(@subscription)
    assert_response :success
    assert_includes response.body, "Edit Subscription"
    assert_includes response.body, @subscription.name
  end

  test "should update financial_subscription" do
    patch financial_subscription_url(@subscription), params: {
      financial_subscription: {
        name: "Updated Netflix",
        description: "Updated description"
      }
    }
    assert_redirected_to @subscription

    @subscription.reload
    assert_equal "Updated Netflix", @subscription.name
    assert_equal "Updated description", @subscription.description
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

  test "mark as paid creates transaction with subscription tag" do
    # Ensure the subscription tag exists
    subscription_tag = @family.tags.find_or_create_by!(name: "Subscription")

    overdue_subscription = FinancialSubscription.create!(
      family: @family,
      account: @account,
      name: "Overdue Subscription",
      amount: 10,
      currency: "USD",
      recurrence: "monthly",
      next_payment_date: Date.current - 1.day
    )

    patch mark_as_paid_financial_subscription_url(overdue_subscription)

    payment = overdue_subscription.financial_subscription_payments.last
    transaction = payment.transaction

    assert_includes transaction.tags, subscription_tag
    assert_equal "Subscription: #{overdue_subscription.name}", transaction.name
  end

  test "should handle errors in mark_as_paid gracefully" do
    # Create a subscription with invalid account to trigger error
    invalid_subscription = FinancialSubscription.create!(
      family: @family,
      account: @account,
      name: "Invalid Subscription",
      amount: 10,
      currency: "USD",
      recurrence: "monthly",
      next_payment_date: Date.current - 1.day
    )

    # Stub mark_as_paid! to raise an error
    FinancialSubscription.any_instance.stubs(:mark_as_paid!).raises(StandardError, "Test error")

    patch mark_as_paid_financial_subscription_url(invalid_subscription)

    assert_redirected_to financial_subscriptions_path
    follow_redirect!
    assert_includes response.body, "Failed to record payment"
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

  test "requires authentication" do
    sign_out users(:dylan)

    get financial_subscriptions_url
    assert_redirected_to new_session_path
  end
end
