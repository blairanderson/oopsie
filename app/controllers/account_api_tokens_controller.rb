class AccountApiTokensController < ApplicationController
  def create
    token, secret = ApiToken.issue(name: api_token_params[:name], user: Current.user)
    if secret
      flash[:notice] = "Created key “#{token.name}”. Copy it now; Oopsie will not show the full value again."
      flash[:api_token] = secret
      redirect_to account_path
    else
      redirect_to account_path, alert: token.errors.full_messages.to_sentence
    end
  end

  def destroy
    token = Current.user.api_tokens.active.find(params[:id])
    token.revoke!
    redirect_to account_path, notice: "Revoked key “#{token.name}”. Requests using it will fail immediately."
  end

  private

  def api_token_params
    params.require(:api_token).permit(:name)
  end
end
