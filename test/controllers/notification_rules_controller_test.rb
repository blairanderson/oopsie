require "test_helper"

class NotificationRulesControllerTest < ActionDispatch::IntegrationTest
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
    sign_in_as(users(:one))
    @project = projects(:myapp)
    @rule = notification_rules(:email_rule)
  end

  test "settings page shows API key" do
    get settings_project_url(@project)
    assert_response :success
    assert_select "code", /#{@project.api_key}/
  end

  test "settings page lists notification rules" do
    get settings_project_url(@project)
    assert_response :success
    assert_select "td code", "admin@example.com"
  end

  test "creates an email notification rule" do
    assert_difference "NotificationRule.count", 1 do
      post project_notification_rules_url(@project), params: {
        notification_rule: { channel: "email", destination: "dev@example.com" }
      }
    end
    assert_redirected_to settings_project_path(@project)
  end

  test "creates a webhook notification rule" do
    assert_difference "NotificationRule.count", 1 do
      post project_notification_rules_url(@project), params: {
        notification_rule: { channel: "webhook", destination: "https://hooks.slack.com/test" }
      }
    end
    assert_redirected_to settings_project_path(@project)
    assert_equal "webhook", NotificationRule.last.channel
  end

  test "creates a webhook notification rule with an optional header" do
    assert_difference "NotificationRule.count", 1 do
      post project_notification_rules_url(@project), params: {
        notification_rule: {
          channel: "webhook",
          destination: "https://hooks.example.com/test",
          webhook_header_name: "Authorization",
          webhook_header_value: "Bearer secret"
        }
      }
    end

    assert_redirected_to settings_project_path(@project)
    assert_equal({ "Authorization" => "Bearer secret" }, NotificationRule.last.webhook_headers)
  end

  test "rejects blank destination" do
    assert_no_difference "NotificationRule.count" do
      post project_notification_rules_url(@project), params: {
        notification_rule: { channel: "email", destination: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "edits a notification rule" do
    get edit_project_notification_rule_url(@project, @rule)
    assert_response :success
    assert_select "form"
  end

  test "updates a notification rule" do
    patch project_notification_rule_url(@project, @rule), params: {
      notification_rule: { destination: "new@example.com" }
    }
    assert_redirected_to settings_project_path(@project)
    assert_equal "new@example.com", @rule.reload.destination
  end

  test "deletes a notification rule" do
    assert_difference "NotificationRule.count", -1 do
      delete project_notification_rule_url(@project, @rule)
    end
    assert_redirected_to settings_project_path(@project)
  end

  test "toggles a notification rule off" do
    assert @rule.enabled?
    patch toggle_project_notification_rule_url(@project, @rule)
    assert_redirected_to settings_project_path(@project)
    assert_not @rule.reload.enabled?
  end

  test "toggles a notification rule back on" do
    @rule.update!(enabled: false)
    patch toggle_project_notification_rule_url(@project, @rule)
    assert_redirected_to settings_project_path(@project)
    assert @rule.reload.enabled?
  end

  test "test_send delivers an email to the destination" do
    assert_emails 1 do
      post test_send_project_notification_rules_url(@project), params: {
        notification_rule: { channel: "email", destination: "qa@example.com" }
      }
    end
    assert_redirected_to settings_project_path(@project)
    assert_match "qa@example.com", flash[:notice]
    assert_equal [ "qa@example.com" ], ActionMailer::Base.deliveries.last.to
  end

  test "test_send rejects blank destination" do
    assert_emails 0 do
      post test_send_project_notification_rules_url(@project), params: {
        notification_rule: { channel: "email", destination: "" }
      }
    end
    assert_redirected_to settings_project_path(@project)
    assert_match(/destination/i, flash[:alert])
  end

  test "test_send accepts PATCH for edit-form submission" do
    assert_emails 1 do
      patch test_send_project_notification_rules_url(@project), params: {
        notification_rule: { channel: "email", destination: "patch@example.com" }
      }
    end
    assert_redirected_to settings_project_path(@project)
  end

  test "test_send rejects invalid webhook URL" do
    assert_emails 0 do
      post test_send_project_notification_rules_url(@project), params: {
        notification_rule: { channel: "webhook", destination: "not-a-url" }
      }
    end
    assert_redirected_to settings_project_path(@project)
    assert flash[:alert].present?
  end

  test "test_send delivers an optional webhook header" do
    http = RecordingHttp.new
    original_http_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| http }

    begin
      post test_send_project_notification_rules_url(@project), params: {
        notification_rule: {
          channel: "webhook",
          destination: "https://hooks.example.com/test",
          webhook_header_name: "Authorization",
          webhook_header_value: "Bearer secret"
        }
      }
    ensure
      Net::HTTP.define_singleton_method(:new, original_http_new)
    end

    assert_redirected_to settings_project_path(@project)
    assert_equal "Bearer secret", http.last_request["Authorization"]
  end

  test "form renders Send Test button" do
    get edit_project_notification_rule_url(@project, @rule)
    assert_response :success
    assert_select "button[formaction*='test_send']", text: /Send Test/
  end

  test "form renders optional webhook header fields" do
    get edit_project_notification_rule_url(@project, @rule)
    assert_response :success
    assert_select "input[name='notification_rule[webhook_header_name]']"
    assert_select "input[name='notification_rule[webhook_header_value]']"
  end
end
