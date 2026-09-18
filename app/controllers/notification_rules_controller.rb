class NotificationRulesController < ApplicationController
  before_action :set_project
  before_action :set_notification_rule, only: [ :edit, :update, :destroy, :toggle ]

  def create
    @notification_rule = @project.notification_rules.build(notification_rule_params)

    if @notification_rule.save
      redirect_to settings_project_path(@project), notice: "Notification rule created."
    else
      @notification_rules = @project.notification_rules.order(:created_at)
      render "projects/settings", status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @notification_rule.update(notification_rule_params)
      redirect_to settings_project_path(@project), notice: "Notification rule updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @notification_rule.destroy
    redirect_to settings_project_path(@project), notice: "Notification rule deleted."
  end

  def toggle
    @notification_rule.update!(enabled: !@notification_rule.enabled)
    redirect_to settings_project_path(@project),
      notice: "Rule #{@notification_rule.enabled? ? 'enabled' : 'disabled'}."
  end

  def test_send
    channel = notification_rule_params[:channel].to_s
    destination = notification_rule_params[:destination].to_s.strip

    if destination.blank?
      redirect_to settings_project_path(@project),
        alert: "Enter a destination before sending a test."
      return
    end

    case channel
    when "email"
      OopsieMailer.test_notification(destination: destination, project: @project).deliver_now
      redirect_to settings_project_path(@project),
        notice: "Test email sent to #{destination}. Check your inbox."
    when "webhook"
      result = WebhookDelivery.call(
        url: destination,
        headers: webhook_headers_from(notification_rule_params),
        payload: WebhookTestProbe.payload(project: @project)
      )
      if result.delivered
        redirect_to settings_project_path(@project),
          notice: "Test webhook delivered (HTTP #{result.http_status})."
      else
        redirect_to settings_project_path(@project),
          alert: "Test webhook failed: #{result.failure["message"]}"
      end
    else
      redirect_to settings_project_path(@project),
        alert: "Unknown channel: #{channel}"
    end
  rescue => e
    Rails.logger.warn "[Oopsie] Test send failed: #{e.class}: #{e.message}"
    redirect_to settings_project_path(@project),
      alert: "Test send failed: #{e.message}"
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_notification_rule
    @notification_rule = @project.notification_rules.find(params[:id])
  end

  def notification_rule_params
    params.require(:notification_rule).permit(:channel, :destination, :webhook_header_name, :webhook_header_value)
  end

  def webhook_headers_from(attributes)
    name = attributes[:webhook_header_name].to_s.strip
    value = attributes[:webhook_header_value].to_s.strip
    return {} if name.blank? && value.blank?

    { name => value }
  end
end
