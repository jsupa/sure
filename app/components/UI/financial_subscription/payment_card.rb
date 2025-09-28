class UI::FinancialSubscription::PaymentCard < ApplicationComponent
  attr_reader :payment

  def initialize(payment:)
    @payment = payment
  end

  def amount_display
    payment.amount_money&.format || "#{payment.currency} #{payment.amount}"
  end

  def payment_date_display
    payment.payment_date.strftime("%B %d, %Y")
  end
end
