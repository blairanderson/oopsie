class OopsieMailer < ApplicationMailer
  def error_notification(notification_rule:, error_group:, occurrence:, is_regression:, manual: false)
    @error_group = error_group
    @occurrence = occurrence
    @project = error_group.project
    @is_regression = is_regression
    @manual = manual
    @url = project_error_group_url(@project, @error_group)

    subject = if manual
      "[#{@project.name}] Manual: #{error_group.error_class}"
    elsif is_regression
      "[#{@project.name}] Regression: #{error_group.error_class}"
    else
      "[#{@project.name}] New: #{error_group.error_class}"
    end

    mail(to: notification_rule.destination, subject: subject)
  end

  def test_notification(destination:, project:)
    @project = project
    mail(to: destination, subject: "[#{@project.name}] Oopsie test notification")
  end
end
