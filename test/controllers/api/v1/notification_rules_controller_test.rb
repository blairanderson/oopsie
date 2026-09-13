require "test_helper"

class Api::V1::NotificationRulesControllerTest < ActionDispatch::IntegrationTest
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
end
