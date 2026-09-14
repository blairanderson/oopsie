class WebhookDeliveryJob < ApplicationJob
  queue_as :default
  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 30.seconds, attempts: 3

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

    deliver_webhook(rule.destination, payload, rule.webhook_headers)
  end

  private

  def deliver_webhook(url, payload, headers = {})
    uri = URI.parse(url)
    return unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.path.presence || "/")
    request["Content-Type"] = "application/json"
    headers.each { |name, value| request[name] = value }
    request.body = payload.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn "[Oopsie] Webhook delivery to #{url} returned #{response.code}"
    end
  end
end
