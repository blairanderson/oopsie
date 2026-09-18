require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "issues a user token and authenticates the plaintext once" do
    token, secret = ApiToken.issue(name: "chatgpt", user: users(:one))

    assert token.persisted?
    assert_equal 8, token.token_prefix.length
    assert_not_equal secret, token.token_digest
    assert_equal token, ApiToken.authenticate(secret)
    assert_nil ApiToken.authenticate("nope")
  end

  test "revoked tokens stop authenticating" do
    token, secret = ApiToken.issue(name: "grok", user: users(:one))
    token.revoke!

    assert token.revoked?
    assert_nil ApiToken.authenticate(secret)
  end

  test "rejects a second active token with the same name on a project" do
    ApiToken.issue(name: "chatgpt", project: projects(:myapp))
    duplicate, secret = ApiToken.issue(name: "chatgpt", project: projects(:myapp))

    assert_nil secret
    assert_not duplicate.persisted?
    assert duplicate.errors[:name].present?
  end

  test "allows reusing a name after revoke" do
    token, = ApiToken.issue(name: "chatgpt", project: projects(:myapp))
    token.revoke!

    replacement, secret = ApiToken.issue(name: "chatgpt", project: projects(:myapp))
    assert replacement.persisted?
    assert secret.present?
  end

  test "records light telemetry" do
    token, = ApiToken.issue(name: "grok", project: projects(:myapp))
    token.record_use!(client: "mcp/chatgpt")
    token.reload

    assert_equal 1, token.requests_count
    assert_equal "mcp/chatgpt", token.last_seen_client
    assert token.last_used_at
  end

  test "requires exactly one owner" do
    token = ApiToken.new(name: "x", token_digest: "a", token_prefix: "b")
    assert_not token.valid?
    assert token.errors[:base].present?
  end
end
