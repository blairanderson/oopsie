class WebhookDeliveryJob < ApplicationJob
  queue_as :default
  retry_on WebhookDelivery::TimeoutError, wait: 30.seconds, attempts: 3

  def perform(notification_rule_id:, error_group_id:, occurrence_id:, is_regression: false, manual: false)
    rule = NotificationRule.find_by(id: notification_rule_id)
    return unless rule&.enabled?

    error_group = ErrorGroup.find_by(id: error_group_id)
    return unless error_group

    occurrence = Occurrence.find_by(id: occurrence_id)
    return unless occurrence

    project = error_group.project

    payload = {
      event: is_regression ? "regression" : "new_error",
      project: { id: project.id, name: project.name },
      error_group: {
        id: error_group.id,
        error_class: error_group.error_class,
        message: error_group.message,
        status: error_group.status,
        occurrences_count: error_group.occurrences_count,
        first_seen_at: error_group.first_seen_at.iso8601,
        last_seen_at: error_group.last_seen_at.iso8601
      },
      occurrence: {
        id: occurrence.id,
        message: occurrence.message,
        environment: occurrence.environment,
        occurred_at: occurrence.occurred_at.iso8601
      }
    }
    payload[:manual] = true if manual

    result = WebhookDelivery.call(url: rule.destination, headers: rule.webhook_headers, payload: payload)
    raise WebhookDelivery::TimeoutError, result.failure["message"] if result.retryable?
    unless result.delivered
      Rails.logger.warn "[Oopsie] Webhook delivery to #{rule.destination_masked} failed: #{result.failure&.fetch("message", "unknown error")}"
    end
  end
end
