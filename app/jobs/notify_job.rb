class NotifyJob < ApplicationJob
  queue_as :default

  def perform(error_group_id:, occurrence_id:, is_regression: false, manual: false)
    error_group = ErrorGroup.find_by(id: error_group_id)
    return unless error_group

    occurrence = Occurrence.find_by(id: occurrence_id)
    return unless occurrence

    project = error_group.project
    event = is_regression ? "regression" : "new_error"
    rules = project.notification_rules.where(enabled: true)

    rules.find_each do |rule|
      next unless manual || rule.notify_for_event?(event)

      case rule.channel
      when "email"
        OopsieMailer.error_notification(
          notification_rule: rule,
          error_group: error_group,
          occurrence: occurrence,
          is_regression: is_regression,
          manual: manual
        ).deliver_later
      when "webhook"
        WebhookDeliveryJob.perform_later(
          notification_rule_id: rule.id,
          error_group_id: error_group.id,
          occurrence_id: occurrence.id,
          is_regression: is_regression,
          manual: manual
        )
      end
    end
  end
end
