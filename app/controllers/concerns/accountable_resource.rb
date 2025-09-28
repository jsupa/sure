module AccountableResource
  extend ActiveSupport::Concern

  included do
    include Periodable

    before_action :set_account, only: [ :show, :edit, :update ]
    before_action :set_link_options, only: :new
  end

  class_methods do
    def permitted_accountable_attributes(*attrs)
      @permitted_accountable_attributes = attrs if attrs.any?
      @permitted_accountable_attributes ||= [ :id ]
    end
  end

  def new
    @account = Current.family.accounts.build(
      currency: Current.family.currency,
      accountable: accountable_type.new
    )
  end

  def show
    @chart_view = params[:chart_view] || "balance"
    @q = params.fetch(:q, {}).permit(:search)
    entries = @account.entries.search(@q).reverse_chronological

    @pagy, @entries = pagy(entries, limit: params[:per_page] || "10")
  end

  def edit
  end

  def create
    @account = Current.family.accounts.create_and_sync(account_params.except(:return_to))
    @account.lock_saved_attributes!

    redirect_to account_params[:return_to].presence || @account, notice: t("accounts.create.success", type: accountable_type.name.underscore.humanize)
  end

  def update
    balance_provided = account_params[:balance].present?
    currency_changing = account_params[:currency].present? && account_params[:currency] != @account.currency

    # If both balance and currency are being updated, handle currency change first
    # then set the balance as if it's already in the new currency
    if balance_provided && currency_changing
      # Convert currency first without converting the balance
      conversion_result = @account.convert_currency(account_params[:currency], convert_balance: false)
      unless conversion_result.success?
        @error_message = conversion_result.error
        render :edit, status: :unprocessable_entity
        return
      end

      # Now set the balance as if it's in the new currency
      @account.reload # Reload to get updated currency
      result = @account.set_current_balance(account_params[:balance].to_d)
      unless result.success?
        @error_message = result.error_message
        render :edit, status: :unprocessable_entity
        return
      end
      @account.sync_later

      flash_message = "#{accountable_type.name.underscore.humanize} currency converted to #{account_params[:currency]}"
    else
      # Handle balance update if provided (and currency is not changing)
      if balance_provided
        result = @account.set_current_balance(account_params[:balance].to_d)
        unless result.success?
          @error_message = result.error_message
          render :edit, status: :unprocessable_entity
          return
        end
        @account.sync_later
      end

      # Handle currency change if provided (and balance is not being updated)
      if currency_changing
        conversion_result = @account.convert_currency(account_params[:currency])
        unless conversion_result.success?
          @error_message = conversion_result.error
          render :edit, status: :unprocessable_entity
          return
        end

        flash_message = "#{accountable_type.name.underscore.humanize} currency converted to #{account_params[:currency]}"
      end
    end

    # Update remaining account attributes (excluding currency since it's handled above)
    update_params = account_params.except(:return_to, :balance, :currency)
    unless @account.update(update_params)
      @error_message = @account.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
      return
    end

    @account.lock_saved_attributes!

    # Use conversion message if currency was changed, otherwise use default message
    notice_message = flash_message || t("accounts.update.success", type: accountable_type.name.underscore.humanize)
    redirect_back_or_to account_path(@account), notice: notice_message
  end

  private
    def set_link_options
      @show_us_link = Current.family.can_connect_plaid_us?
      @show_eu_link = Current.family.can_connect_plaid_eu?
    end

    def accountable_type
      controller_name.classify.constantize
    end

    def set_account
      @account = Current.family.accounts.find(params[:id])
    end

    def account_params
      params.require(:account).permit(
        :name, :balance, :subtype, :currency, :accountable_type, :return_to,
        accountable_attributes: self.class.permitted_accountable_attributes
      )
    end
end
