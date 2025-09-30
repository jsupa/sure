class FinancialSubscription < ApplicationRecord
  include Monetizable

  # Average number of days per year, including leap years (365 days + 1 extra day every 4 years)
  AVERAGE_DAYS_PER_YEAR = 365.25

  # Average number of days per month (average days per year divided by 12 months)
  AVERAGE_DAYS_PER_MONTH = AVERAGE_DAYS_PER_YEAR / 12.0

  belongs_to :account
  belongs_to :family
  has_many :financial_subscription_payments, dependent: :destroy
  has_many :transactions, through: :financial_subscription_payments, source: :payment_transaction

  validates :name, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :recurrence, presence: true
  validates :next_payment_date, presence: true
  validate :account_belongs_to_family

  monetize :amount

  enum :recurrence, {
    daily: "daily",
    weekly: "weekly",
    monthly: "monthly",
    quarterly: "quarterly",
    yearly: "yearly"
  }

  scope :for_family, ->(family) { where(family: family) }
  scope :overdue, -> { where("next_payment_date < ?", Date.current) }
  scope :upcoming, ->(days = 7) { where(next_payment_date: Date.current..days.days.from_now) }
  scope :active, -> { where("next_payment_date >= ?", Date.current) }

  class << self
    def calculate_monthly_expense(subscriptions, target_currency)
      total_amount = subscriptions.sum do |subscription|
        subscription.monthly_equivalent_amount_in_currency(target_currency)
      end
      Money.new(total_amount, target_currency)
    end

    def calculate_yearly_expense(subscriptions, target_currency)
      total_amount = subscriptions.sum do |subscription|
        subscription.yearly_equivalent_amount_in_currency(target_currency)
      end
      Money.new(total_amount, target_currency)
    end
  end

  def overdue?
    next_payment_date < Date.current
  end

  def days_overdue
    return 0 unless overdue?
    (Date.current - next_payment_date).to_i
  end

  def calculate_next_payment_date(from_date = next_payment_date)
    case recurrence
    when "daily"
      from_date + 1.day
    when "weekly"
      from_date + 1.week
    when "monthly"
      from_date + 1.month
    when "quarterly"
      from_date + 3.months
    when "yearly"
      from_date + 1.year
    else
      raise ArgumentError, "Unknown recurrence: #{recurrence}"
    end
  end

  # Average number of weeks per year (365.25 days/year divided by 7 days/week)
  AVERAGE_WEEKS_PER_YEAR = 365.25 / 7.0

  # Average number of weeks per month (AVERAGE_WEEKS_PER_YEAR ÷ 12 months/year)
  AVERAGE_WEEKS_PER_MONTH = AVERAGE_WEEKS_PER_YEAR / 12.0

  def monthly_equivalent_amount
    return 0 if amount.nil?

    case recurrence
    when "daily"
      amount.to_f * 30.44 # Average days per month
    when "weekly"
      amount.to_f * AVERAGE_WEEKS_PER_MONTH # Average weeks per month
    when "monthly"
      amount.to_f
    when "quarterly"
      amount.to_f / 3.0
    when "yearly"
      amount.to_f / 12.0
    else
      0.0
    end
  end

  def yearly_equivalent_amount
    return 0 if amount.nil?

    case recurrence
    when "daily"
      amount.to_f * 365.25 # Including leap years
    when "weekly"
      amount.to_f * AVERAGE_WEEKS_PER_YEAR # Average weeks per year
    when "monthly"
      amount.to_f * 12
    when "quarterly"
      amount.to_f * 4
    when "yearly"
      amount.to_f
    else
      0.0
    end
  end

  def monthly_equivalent_amount_in_currency(target_currency)
    return 0 if amount.nil?

    base_amount = monthly_equivalent_amount

    if currency == target_currency
      base_amount
    else
      # Try to convert using Money class
      begin
        money_obj = Money.new(base_amount, currency)
        converted_money = money_obj.exchange_to(target_currency)
        converted_money.amount
      rescue Money::ConversionError => e
        Rails.logger.warn "Currency conversion failed for #{name} (#{currency} -> #{target_currency}): #{e.message}"

        # Try to use a reasonable fallback rate if this is a common conversion
        fallback_rate = get_fallback_exchange_rate(currency, target_currency)
        if fallback_rate
          Rails.logger.info "Using fallback rate #{fallback_rate} for #{currency} -> #{target_currency}"
          base_amount * fallback_rate
        else
          Rails.logger.warn "No fallback rate available, using original amount"
          # Return original amount as fallback - this will be in wrong currency but at least shows a value
          base_amount
        end
      end
    end
  end

  def yearly_equivalent_amount_in_currency(target_currency)
    return 0 if amount.nil?

    base_amount = yearly_equivalent_amount

    if currency == target_currency
      base_amount
    else
      # Try to convert using Money class
      begin
        money_obj = Money.new(base_amount, currency)
        converted_money = money_obj.exchange_to(target_currency)
        converted_money.amount
      rescue Money::ConversionError => e
        Rails.logger.warn "Currency conversion failed for #{name} (#{currency} -> #{target_currency}): #{e.message}"

        # Try to use a reasonable fallback rate
        fallback_rate = get_fallback_exchange_rate(currency, target_currency)
        if fallback_rate
          base_amount * fallback_rate
        else
          # Return original amount as fallback - this will be in wrong currency but at least shows a value
          base_amount
        end
      end
    end
  end

  def mark_as_paid!(payment_date = Date.current)
    transaction do
      # Find or create the Subscription tag
      subscription_tag = family.tags.find_or_create_by!(name: "Subscription")

      # Find or create the Subscriptions expense category
      subscriptions_category = family.categories.find_or_create_by!(
        name: "Subscriptions",
        classification: "expense"
      ) do |category|
        category.color = Category::COLORS.sample
        category.lucide_icon = "repeat"
      end

      # Create transaction as expense with category
      transaction_record = Transaction.new(
        kind: "standard",
        category: subscriptions_category
      )

      # Add the subscription tag
      transaction_record.taggings.build(tag: subscription_tag)

      # Create entry for this transaction
      entry = account.entries.build(
        name: "Subscription: #{name}",
        date: payment_date,
        amount: amount, # Positive for expense (following app conventions)
        currency: currency,
        entryable: transaction_record
      )

      # Save the entry (which will save the transaction)
      entry.save!

      # Create payment record
      payment = financial_subscription_payments.create!(
        payment_date: payment_date,
        amount: amount,
        currency: currency,
        payment_transaction: transaction_record
      )

      # Update next payment date
      update!(next_payment_date: calculate_next_payment_date(payment_date))

      payment
    end
  end

  private

    def get_fallback_exchange_rate(from_currency, to_currency)
      Rails.application.config.fallback_exchange_rates&.dig(from_currency, to_currency)
    end

    def account_belongs_to_family
      return unless account_id.present? && family.present?

      unless family.accounts.exists?(account_id)
        errors.add(:account, "must belong to your family")
      end
    end
end
