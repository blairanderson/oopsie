require "test_helper"

class NotificationRuleTest < ActiveSupport::TestCase
  test "valid email rule" do
    rule = NotificationRule.new(
      project: projects(:myapp),
      channel: :email,
      destination: "dev@example.com"
    )
    assert rule.valid?
    assert rule.enabled?, "should default to enabled"
  end

  test "valid webhook rule" do
    rule = NotificationRule.new(
      project: projects(:myapp),
      channel: :webhook,
      destination: "https://hooks.example.com/notify"
    )
    assert rule.valid?
  end

  test "valid webhook rule with custom headers" do
    rule = NotificationRule.new(
      project: projects(:myapp),
      channel: :webhook,
      destination: "https://hooks.example.com/notify",
      webhook_headers: { "Authorization" => "Bearer secret" }
    )

    assert rule.valid?
    assert_equal({ "Authorization" => "Bearer secret" }, rule.webhook_headers)
  end

  test "rejects webhook headers with a newline" do
    rule = NotificationRule.new(
      project: projects(:myapp),
      channel: :webhook,
      destination: "https://hooks.example.com/notify",
      webhook_headers: { "Authorization" => "Bearer secret\nX-Injected: true" }
    )

    assert_not rule.valid?
    assert_match(/valid HTTP header/, rule.errors[:webhook_headers].join)
  end

  test "defaults to all supported events" do
    rule = NotificationRule.create!(
      project: projects(:myapp),
      channel: :webhook,
      destination: "https://hooks.example.com/notify"
    )

    assert_equal %w[new_error regression], rule.events
  end

  test "normalizes event aliases" do
    rule = NotificationRule.new(
      project: projects(:myapp),
      channel: :webhook,
      destination: "https://hooks.example.com/notify",
      events: [ "error.created", "error.regressed" ]
    )

    assert rule.valid?
    assert_equal %w[new_error regression], rule.events
  end

  test "rejects unsupported events" do
    rule = NotificationRule.new(
      project: projects(:myapp),
      channel: :webhook,
      destination: "https://hooks.example.com/notify",
      events: [ "error.deleted" ]
    )

    assert_not rule.valid?
    assert_match(/unsupported event/, rule.errors[:events].join)
  end

  test "requires channel and destination" do
    rule = NotificationRule.new(project: projects(:myapp))
    assert_not rule.valid?
    assert_includes rule.errors[:channel], "can't be blank"
    assert_includes rule.errors[:destination], "can't be blank"
  end
end
