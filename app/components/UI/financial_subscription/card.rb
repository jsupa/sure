class UI::FinancialSubscription::Card < ApplicationComponent
  attr_reader :subscription, :show_actions

  def initialize(subscription:, show_actions: true)
    @subscription = subscription
    @show_actions = show_actions
  end

  def status_color
    return "text-red-500" if subscription.overdue?
    "text-green-500"
  end

  def status_text
    if subscription.overdue?
      "#{subscription.days_overdue} days overdue"
    else
      "Next payment: #{subscription.next_payment_date.strftime('%B %d, %Y')}"
    end
  end

  def recurrence_text
    subscription.recurrence.humanize
  end

  def amount_display
    subscription.amount_money&.format || "#{subscription.currency} #{subscription.amount}"
  end
end
