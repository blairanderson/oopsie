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
      result = deliver_test_webhook(destination, webhook_headers_from(notification_rule_params))
      if result[:ok]
        redirect_to settings_project_path(@project),
          notice: "Test webhook delivered (HTTP #{result[:code]})."
      else
        redirect_to settings_project_path(@project),
          alert: "Test webhook failed: #{result[:error]}"
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

  def deliver_test_webhook(url, headers = {})
    uri = URI.parse(url)
    return { ok: false, error: "must be an HTTP or HTTPS URL" } unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.path.presence || "/")
    request["Content-Type"] = "application/json"
    headers.each { |name, value| request[name] = value }
    request.body = { event: "test", project: { id: @project.id, name: @project.name }, message: "Oopsie test webhook" }.to_json

    response = http.request(request)
    if response.is_a?(Net::HTTPSuccess)
      { ok: true, code: response.code }
    else
      { ok: false, error: "HTTP #{response.code}" }
    end
  rescue URI::InvalidURIError
    { ok: false, error: "invalid URL" }
  rescue => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

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
