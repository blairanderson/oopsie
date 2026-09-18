class AccountsController < ApplicationController
  def show
    @user = Current.user
    @api_tokens = @user.api_tokens.order(Arel.sql("CASE WHEN revoked_at IS NULL THEN 0 ELSE 1 END"), created_at: :desc)
  end

  def rotate_key
    Current.user.regenerate_api_key!
    redirect_to account_path, notice: "API key regenerated. Update your CLI and integrations with the new key."
  end
end
