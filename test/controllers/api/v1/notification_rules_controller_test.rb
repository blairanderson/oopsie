require "test_helper"

class Api::V1::NotificationRulesControllerTest < ActionDispatch::IntegrationTest
  class RecordingHttp
    attr_reader :last_request

    def use_ssl=(_value)
    end

    def open_timeout=(_value)
    end

    def read_timeout=(_value)
    end

    def request(request)
      @last_request = request
      Net::HTTPSuccess.new("1.1", "204", "No Content")
    end
  end

  setup do
    @project = projects(:myapp)
    @project_headers = {
      "Authorization" => "Bearer #{@project.api_key}",
      "Content-Type" => "application/json"
    }
    @user = users(:one)
    @user_headers = {
      "Authorization" => "Bearer #{@user.api_key}",
      "Content-Type" => "application/json"
    }
  end

  test "lists notification rules for a project key" do
    get api_v1_notification_rules_url, headers: @project_headers
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 1, json["notification_rules"].length

    rule = json["notification_rules"].first
    assert_equal "email", rule["channel"]
    assert_not rule.key?("destination")
    assert_equal "a***@example.com", rule["destination_masked"]
    assert_equal %w[new_error regression], rule["events"]
    assert rule["enabled"]
    assert_equal false, rule["headers_configured"]
  end

  test "creates webhook notification rule for a project key" do
    assert_difference "NotificationRule.count", 1 do
      post api_v1_notification_rules_url,
        params: {
          notification_rule: {
            channel: "webhook",
            destination: "https://hooks.example.com/secret/path",
            headers: { "Authorization" => "Bearer secret" },
            events: [ "error.created" ]
          }
        }.to_json,
        headers: @project_headers
    end

    assert_response :created
    json = JSON.parse(response.body)
    rule = json["notification_rule"]
    assert_equal "webhook", rule["channel"]
    assert_not rule.key?("destination")
    assert_not rule.key?("headers")
    assert_equal "https://hooks.example.com/...", rule["destination_masked"]
    assert_equal [ "new_error" ], rule["events"]
    assert_equal true, rule["headers_configured"]
    assert_equal [ "new_error" ], NotificationRule.last.events
    assert_equal({ "Authorization" => "Bearer secret" }, NotificationRule.last.webhook_headers)
  end

  test "user key requires project context" do
    get api_v1_notification_rules_url, headers: @user_headers
    assert_response :bad_request
  end

  test "user key can create with project header" do
    headers = @user_headers.merge("X-Project-Id" => @project.id.to_s)

    assert_difference "NotificationRule.count", 1 do
      post api_v1_notification_rules_url,
        params: {
          notification_rule: {
            channel: "webhook",
            destination: "https://hooks.example.com/user-key",
            events: [ "error.reopened" ],
            enabled: false
          }
        }.to_json,
        headers: headers
    end

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal [ "regression" ], json.dig("notification_rule", "events")
    assert_equal false, json.dig("notification_rule", "enabled")
  end

  test "rejects invalid event names" do
    assert_no_difference "NotificationRule.count" do
      post api_v1_notification_rules_url,
        params: {
          notification_rule: {
            channel: "webhook",
            destination: "https://hooks.example.com/test",
            events: [ "error.deleted" ]
          }
        }.to_json,
        headers: @project_headers
    end

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_match(/unsupported event/, json.dig("errors", "events").join)
  end

  test "rejects invalid webhook URL" do
    assert_no_difference "NotificationRule.count" do
      post api_v1_notification_rules_url,
        params: {
          notification_rule: {
            channel: "webhook",
            destination: "not-a-url"
          }
        }.to_json,
        headers: @project_headers
    end

    assert_response :unprocessable_entity
  end

  test "rejects invalid channel" do
    assert_no_difference "NotificationRule.count" do
      post api_v1_notification_rules_url,
        params: {
          notification_rule: {
            channel: "sms",
            destination: "https://hooks.example.com/test"
          }
        }.to_json,
        headers: @project_headers
    end

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_match(/included in the list/, json.dig("errors", "channel").join)
  end

  test "setup webhook creates then returns the same rule for an exact match" do
    params = {
      notification_rule: {
        destination: "https://hooks.example.com/setup",
        headers: { "Authorization" => "Bearer secret" },
        events: [ "new_error" ]
      }
    }

    assert_difference "NotificationRule.count", 1 do
      post setup_webhook_api_v1_notification_rules_url,
        params: params.to_json,
        headers: @project_headers
    end
    assert_response :created
    first = JSON.parse(response.body)
    assert first["created"]
    assert_not first["notification_rule"].key?("destination")
    assert_equal "https://hooks.example.com/...", first.dig("notification_rule", "destination_masked")

    assert_no_difference "NotificationRule.count" do
      post setup_webhook_api_v1_notification_rules_url,
        params: params.to_json,
        headers: @project_headers
    end
    assert_response :success
    second = JSON.parse(response.body)
    assert_equal false, second["created"]
    assert_equal first.dig("notification_rule", "id"), second.dig("notification_rule", "id")
  end

  test "tests a persisted webhook by id without accepting a destination" do
    rule = @project.notification_rules.create!(
      channel: :webhook,
      destination: "https://hooks.example.com/test?token=secret",
      webhook_headers: { "X-Token" => "abc" },
      enabled: false
    )
    http = RecordingHttp.new
    original_http_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| http }

    begin
      post test_api_v1_notification_rule_url(rule),
        params: { destination: "https://evil.example" }.to_json,
        headers: @project_headers
    ensure
      Net::HTTP.define_singleton_method(:new, original_http_new)
    end

    assert_response :success
    json = JSON.parse(response.body)
    delivery = json["delivery"]
    assert_equal rule.id, delivery["rule_id"]
    assert delivery["delivered"]
    assert_equal 204, delivery["http_status"]
    assert_equal "connectivity_probe", delivery["payload_kind"]
    assert_nil delivery["failure"]
    assert_not json.key?("destination")
    assert_equal "/test?token=secret", http.last_request.path
    assert_equal "abc", http.last_request["X-Token"]
    payload = JSON.parse(http.last_request.body)
    assert_equal "test", payload["event"]
    assert_equal @project.name, payload.dig("project", "name")
  end

  test "webhook test rejects email rules" do
    post test_api_v1_notification_rule_url(notification_rules(:email_rule)),
      headers: @project_headers

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_match(/webhook/, json.dig("errors", "channel").join)
  end
end
