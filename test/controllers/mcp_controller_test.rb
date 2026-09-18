require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  class RecordingHttp
    attr_reader :last_request

    def use_ssl=(_value); end
    def open_timeout=(_value); end
    def read_timeout=(_value); end

    def request(request)
      @last_request = request
      Net::HTTPSuccess.new("1.1", "204", "No Content")
    end
  end

  setup do
    @project = projects(:myapp)
    @user = users(:one)
    @user_headers = {
      "Authorization" => "Bearer #{@user.api_key}",
      "Content-Type" => "application/json"
    }
    @project_headers = {
      "Authorization" => "Bearer #{@project.api_key}",
      "Content-Type" => "application/json"
    }
  end

  test "rejects missing api key" do
    post mcp_url, params: rpc("initialize", protocolVersion: "2025-06-18"), as: :json

    assert_response :unauthorized
    assert_match(/Bearer/, response.headers["WWW-Authenticate"].to_s)
  end

  test "initialize advertises webhook tools capability" do
    post mcp_url, params: rpc("initialize", protocolVersion: "2025-06-18"), headers: @user_headers, as: :json

    assert_response :success
    result = jsonrpc_result
    assert_equal "2025-06-18", result["protocolVersion"]
    assert result.dig("capabilities", "tools")
    assert_equal "oopsie", result.dig("serverInfo", "name")
  end

  test "lists webhook tools" do
    post mcp_url, params: rpc("tools/list"), headers: @user_headers, as: :json

    names = jsonrpc_result.fetch("tools").map { |tool| tool["name"] }
    assert_equal %w[oopsie_webhook_setup oopsie_webhook_test oopsie_webhook_list], names
  end

  test "initialized notification returns 202" do
    post mcp_url,
      params: { jsonrpc: "2.0", method: "notifications/initialized" },
      headers: @user_headers,
      as: :json

    assert_response :accepted
  end

  test "setup with a user key requires a project and never returns the url" do
    post mcp_url, params: rpc("tools/call", name: "oopsie_webhook_setup", arguments: {
      url: "https://hooks.example.com/secret-path",
      headers: { "Authorization" => "Bearer tok" },
      project: "MyApp"
    }), headers: @user_headers, as: :json

    result = jsonrpc_result
    assert_equal false, result["isError"]
    refute_includes response.body, "secret-path"
    refute_includes response.body, "Bearer tok"
    assert NotificationRule.webhook.exists?(project: @project)
  end

  test "test probes a stored webhook by id" do
    rule = @project.notification_rules.create!(
      channel: :webhook,
      destination: "https://hooks.example.com/test?token=secret",
      webhook_headers: { "X-Token" => "abc" }
    )
    http = RecordingHttp.new
    original_http_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| http }

    begin
      post mcp_url, params: rpc("tools/call", name: "oopsie_webhook_test", arguments: {
        rule_id: rule.id,
        project: @project.id
      }), headers: @user_headers, as: :json
    ensure
      Net::HTTP.define_singleton_method(:new, original_http_new)
    end

    delivery = jsonrpc_result.dig("structuredContent", "delivery")
    assert_equal false, jsonrpc_result["isError"]
    assert_equal true, delivery["delivered"]
    assert_equal "connectivity_probe", delivery["payload_kind"]
    assert_equal "/test?token=secret", http.last_request.path
    refute_includes response.body, "token=secret"
  end

  test "list with a project key uses implicit project scope" do
    @project.notification_rules.create!(
      channel: :webhook,
      destination: "https://hooks.example.com/secret-path"
    )

    post mcp_url, params: rpc("tools/call", name: "oopsie_webhook_list", arguments: {}),
      headers: @project_headers, as: :json

    webhooks = jsonrpc_result.dig("structuredContent", "webhooks")
    assert_equal 1, webhooks.length
    assert_equal "https://hooks.example.com/...", webhooks.dig(0, "destination_masked")
    refute webhooks.dig(0)&.key?("destination")
    refute_includes response.body, "secret-path"
  end

  test "get is not an SSE listener" do
    get mcp_url, headers: @user_headers
    assert_response :method_not_allowed
  end

  private

  def rpc(method, **params)
    payload = { jsonrpc: "2.0", id: 1, method: method }
    payload[:params] = params if params.any?
    payload
  end

  def jsonrpc_result
    assert_response :success
    body = JSON.parse(response.body)
    assert_nil body["error"], body["error"].inspect
    body.fetch("result")
  end
end
