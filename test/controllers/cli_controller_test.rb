require "test_helper"

class CliControllerTest < ActionDispatch::IntegrationTest
  test "documents webhook setup, test, and the MCP adapter" do
    get cli_url

    assert_response :success
    assert_select "h2", text: "Remote MCP (ChatGPT, Grok)"
    assert_includes response.body, "oopsie webhook setup --input-json -"
    assert_includes response.body, "oopsie webhook test"
    assert_includes response.body, "oopsie-mcp"
    assert_includes response.body, "/mcp"
    assert_includes response.body, "/api/v1/notification_rules/setup_webhook"
  end
end
