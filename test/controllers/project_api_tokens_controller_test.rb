require "test_helper"

class ProjectApiTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @project = projects(:myapp)
  end

  test "creates a named project key from settings" do
    get settings_project_url(@project)
    assert_response :success
    assert_select "h2", text: "Named project keys"

    assert_difference "@project.api_tokens.count", 1 do
      post project_api_tokens_url(@project), params: { api_token: { name: "grok" } }
    end
    assert_redirected_to settings_project_path(@project)
  end

  test "revokes a named project key" do
    token, = ApiToken.issue(name: "ingest-ci", project: @project)
    delete project_api_token_url(@project, token)

    assert_redirected_to settings_project_path(@project)
    assert token.reload.revoked?
  end
end
