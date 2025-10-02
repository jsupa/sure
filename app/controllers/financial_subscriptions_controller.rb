class FinancialSubscriptionsController < ApplicationController
  before_action :set_financial_subscription, only: [ :show, :edit, :update, :destroy, :mark_as_paid ]

  def index
    @financial_subscriptions = Current.family.financial_subscriptions.includes(:account)

    @overdue_subscriptions = @financial_subscriptions.overdue.order(:next_payment_date)
    @upcoming_subscriptions = @financial_subscriptions.upcoming(30).order(:next_payment_date)
    @active_subscriptions = @financial_subscriptions.active.order(:next_payment_date)
    # For totals calculation, we need ALL subscriptions (overdue + active)
    @all_active_subscriptions = @financial_subscriptions

    @recent_payments = FinancialSubscriptionPayment
                        .for_family(Current.family)
                        .includes(:financial_subscription, :payment_transaction)
                        .recent
                        .limit(20)

    # Calculate expense analytics with multicurrency support
    family_currency = Current.family.currency

    # Calculate totals for all subscriptions (overdue + active + future)
    @monthly_total = FinancialSubscription.calculate_monthly_expense(@all_active_subscriptions, family_currency)
    @yearly_total = FinancialSubscription.calculate_yearly_expense(@all_active_subscriptions, family_currency)

    # Also calculate just overdue amounts for display
    @monthly_overdue = FinancialSubscription.calculate_monthly_expense(@overdue_subscriptions, family_currency)
    @yearly_overdue = FinancialSubscription.calculate_yearly_expense(@overdue_subscriptions, family_currency)

    # Additional currency information for display
    @family_currency = family_currency
    @has_mixed_currencies = @financial_subscriptions.pluck(:currency).uniq.size > 1
  end

  def new
    @financial_subscription = Current.family.financial_subscriptions.build
  end

  def show
    @payments = @financial_subscription.financial_subscription_payments
                                      .includes(:payment_transaction)
                                      .recent
                                      .limit(50)
  end

  def create
    @financial_subscription = Current.family.financial_subscriptions.build(financial_subscription_params)

    # Safely assign account with proper family validation
    safe_account_assignment(@financial_subscription)

    if @financial_subscription.errors.empty? && @financial_subscription.save
      redirect_to financial_subscriptions_path, notice: "Subscription was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    # Safely assign account with proper family validation
    safe_account_assignment(@financial_subscription)

    if @financial_subscription.errors.empty? && @financial_subscription.update(financial_subscription_params)
      redirect_to financial_subscriptions_path, notice: "Subscription was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @financial_subscription.destroy
    redirect_to financial_subscriptions_path, notice: "Subscription was successfully deleted."
  end

  def mark_as_paid
    begin
      @financial_subscription.mark_as_paid!

      redirect_to financial_subscriptions_path, notice: "Payment recorded successfully."
    rescue => e
      redirect_to financial_subscriptions_path, alert: "Failed to record payment: #{e.message}"
    end
  end

  def active_subscriptions_modal
    @all_subscriptions = Current.family.financial_subscriptions.includes(:account).order(:next_payment_date)
    @upcoming_subscription_ids = @all_subscriptions.upcoming(30).pluck(:id)

    render partial: "active_subscriptions_modal", locals: {
      subscriptions: @all_subscriptions,
      upcoming_ids: @upcoming_subscription_ids
    }
  end

  private

    def set_financial_subscription
      @financial_subscription = Current.family.financial_subscriptions.find(params[:id])
    end

    def financial_subscription_params
      # Exclude account_id from mass assignment for security - handled separately
      params.require(:financial_subscription).permit(
        :name,
        :amount,
        :currency,
        :recurrence,
        :next_payment_date,
        :description
      )
    end

    def safe_account_assignment(subscription)
      # Safely handle account assignment with proper family scoping
      return unless params.dig(:financial_subscription, :account_id).present?

      account = Current.family.accounts.find_by(id: params[:financial_subscription][:account_id])
      if account
        subscription.account = account
      else
        subscription.errors.add(:account, "must belong to your family")
      end
    end
end
