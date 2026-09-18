# frozen_string_literal: true

class WebhookRuleSetup
  Result = Data.define(:rule, :created, :errors) do
    def ok?
      errors.nil?
    end
  end

  def self.call(project:, attributes:)
    attributes = attributes.to_h.symbolize_keys
    if attributes.key?(:headers)
      attributes[:webhook_headers] = attributes.delete(:headers)
    end

    candidate = project.notification_rules.build(attributes.merge(channel: "webhook"))
    unless candidate.valid?
      return Result.new(rule: candidate, created: false, errors: candidate.errors.to_hash(true))
    end

    project.with_lock do
      match = project.notification_rules.webhook.find { |rule| same_configuration?(rule, candidate) }
      return Result.new(rule: match, created: false, errors: nil) if match

      candidate.save!
      Result.new(rule: candidate, created: true, errors: nil)
    end
  end

  def self.same_configuration?(existing, candidate)
    existing.destination == candidate.destination &&
      existing.webhook_headers == candidate.webhook_headers &&
      existing.events == candidate.events &&
      existing.enabled == candidate.enabled
  end
  private_class_method :same_configuration?
end
