require "test_helper"

class WebhookRuleSetupTest < ActiveSupport::TestCase
  setup do
    @project = projects(:myapp)
  end

  test "creates a webhook rule" do
    result = WebhookRuleSetup.call(
      project: @project,
      attributes: {
        destination: "https://hooks.example.com/a",
        events: %w[new_error],
        enabled: true
      }
    )

    assert result.ok?
    assert result.created
    assert_equal "webhook", result.rule.channel
    assert_equal "https://hooks.example.com/a", result.rule.destination
  end

  test "returns the existing rule for an exact configuration match" do
    first = WebhookRuleSetup.call(
      project: @project,
      attributes: {
        destination: "https://hooks.example.com/same",
        headers: { "Authorization" => "Bearer secret" },
        events: %w[new_error regression],
        enabled: true
      }
    )

    assert_no_difference "NotificationRule.count" do
      second = WebhookRuleSetup.call(
        project: @project,
        attributes: {
          destination: "https://hooks.example.com/same",
          webhook_headers: { "Authorization" => "Bearer secret" },
          events: %w[new_error regression],
          enabled: true
        }
      )

      assert second.ok?
      assert_not second.created
      assert_equal first.rule.id, second.rule.id
    end
  end

  test "creates a distinct rule for a near match" do
    WebhookRuleSetup.call(
      project: @project,
      attributes: {
        destination: "https://hooks.example.com/near",
        events: %w[new_error],
        enabled: true
      }
    )

    result = WebhookRuleSetup.call(
      project: @project,
      attributes: {
        destination: "https://hooks.example.com/near",
        events: %w[regression],
        enabled: true
      }
    )

    assert result.ok?
    assert result.created
    assert_equal [ "regression" ], result.rule.events
  end

  test "rejects an invalid destination" do
    result = WebhookRuleSetup.call(
      project: @project,
      attributes: { destination: "not-a-url" }
    )

    assert_not result.ok?
    assert result.errors[:destination].present?
  end
end
