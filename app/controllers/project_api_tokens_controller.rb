class ProjectApiTokensController < ApplicationController
  before_action :set_project

  def create
    token, secret = ApiToken.issue(name: api_token_params[:name], project: @project)
    if secret
      flash[:notice] = "Created key “#{token.name}”. Copy it now; Oopsie will not show the full value again."
      flash[:api_token] = secret
      redirect_to settings_project_path(@project)
    else
      redirect_to settings_project_path(@project), alert: token.errors.full_messages.to_sentence
    end
  end

  def destroy
    token = @project.api_tokens.active.find(params[:id])
    token.revoke!
    redirect_to settings_project_path(@project), notice: "Revoked key “#{token.name}”. Requests using it will fail immediately."
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def api_token_params
    params.require(:api_token).permit(:name)
  end
end
