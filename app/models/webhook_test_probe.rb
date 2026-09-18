# frozen_string_literal: true

class WebhookTestProbe
  PAYLOAD_KIND = "connectivity_probe"

  def self.payload(project:)
    {
      event: "test",
      project: { id: project.id, name: project.name },
      message: "Oopsie test webhook"
    }
  end

  def self.call(project:, rule:)
    WebhookDelivery.call(
      url: rule.destination,
      headers: rule.webhook_headers,
      payload: payload(project: project)
    )
  end
end
