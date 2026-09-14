require "test_helper"

class WebhookDeliveryJobTest < ActiveJob::TestCase
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
    @error_group = @project.error_groups.create!(
      fingerprint: "webhook_delivery_test_fp",
      error_class: "TestError",
      message: "test webhook",
      status: :unresolved,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
    @occurrence = @error_group.occurrences.create!(
      message: "test webhook",
      occurred_at: Time.current,
      environment: "production"
    )
    @rule = notification_rules(:email_rule)
    @rule.update!(
      channel: :webhook,
      destination: "https://hooks.example.com/test",
      webhook_headers: { "Authorization" => "Bearer secret" }
    )
  end

  test "delivers custom headers with the webhook request" do
    http = RecordingHttp.new
    original_http_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| http }

    begin
      WebhookDeliveryJob.perform_now(
        notification_rule_id: @rule.id,
        error_group_id: @error_group.id,
        occurrence_id: @occurrence.id
      )
    ensure
      Net::HTTP.define_singleton_method(:new, original_http_new)
    end

    assert_equal "Bearer secret", http.last_request["Authorization"]
    assert_equal "application/json", http.last_request["Content-Type"]
  end

  test "marks a manually sent webhook payload" do
    http = RecordingHttp.new
    original_http_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| http }

    begin
      WebhookDeliveryJob.perform_now(
        notification_rule_id: @rule.id,
        error_group_id: @error_group.id,
        occurrence_id: @occurrence.id,
        manual: true
      )
    ensure
      Net::HTTP.define_singleton_method(:new, original_http_new)
    end

    payload = JSON.parse(http.last_request.body)
    assert_equal "new_error", payload["event"]
    assert_equal true, payload["manual"]
  end
end
