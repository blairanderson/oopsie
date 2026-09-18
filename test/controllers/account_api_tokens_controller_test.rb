require "test_helper"

class AccountApiTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "creates a named user key and shows the secret once" do
    assert_difference "ApiToken.count", 1 do
      post account_api_tokens_url, params: { api_token: { name: "chatgpt" } }
    end
    assert_redirected_to account_path
    follow_redirect!
    assert_includes response.body, "Created key"
    assert_select "td", text: "chatgpt"
  end

  test "revokes a named user key" do
    token, secret = ApiToken.issue(name: "grok", user: @user)
    delete account_api_token_url(token)

    assert_redirected_to account_path
    assert token.reload.revoked?
    assert_nil ApiToken.authenticate(secret)
  end
end
