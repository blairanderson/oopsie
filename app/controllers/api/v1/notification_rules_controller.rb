module Api
  module V1
    class NotificationRulesController < BaseController
      before_action :require_project!

      def index
        rules = @project.notification_rules.order(:created_at)
        render json: { notification_rules: rules.map { |rule| serialize_rule(rule) } }
      end

      def create
        attributes = notification_rule_params
        if attributes[:channel].present? && !NotificationRule.channels.key?(attributes[:channel])
          render json: {
            error: "Validation failed",
            errors: { channel: [ "Channel is not included in the list" ] }
          }, status: :unprocessable_entity
          return
        end

        rule = @project.notification_rules.build(attributes)

        if rule.save
          render json: { notification_rule: serialize_rule(rule) }, status: :created
        else
          render json: {
            error: "Validation failed",
            errors: rule.errors.to_hash(true)
          }, status: :unprocessable_entity
        end
      end

      def setup_webhook
        result = WebhookRuleSetup.call(project: @project, attributes: webhook_setup_params)
        unless result.ok?
          render json: { error: "Validation failed", errors: result.errors }, status: :unprocessable_entity
          return
        end

        render json: {
          notification_rule: serialize_rule(result.rule),
          created: result.created
        }, status: result.created ? :created : :ok
      end

      def test
        rule = @project.notification_rules.find(params[:id])
        unless rule.webhook?
          render json: {
            error: "Validation failed",
            errors: { channel: [ "must be webhook" ] }
          }, status: :unprocessable_entity
          return
        end

        result = WebhookTestProbe.call(project: @project, rule: rule)
        render json: { delivery: serialize_delivery(rule, result) }
      end

      private

      def notification_rule_params
        permitted = params.require(:notification_rule).permit(:channel, :destination, :enabled, events: [], headers: {})
        headers = permitted.delete(:headers)
        permitted[:webhook_headers] = headers if headers
        permitted
      end

      def webhook_setup_params
        permitted = params.require(:notification_rule).permit(:destination, :enabled, events: [], headers: {})
        headers = permitted.delete(:headers)
        permitted[:webhook_headers] = headers if headers
        permitted
      end

      def serialize_rule(rule)
        {
          id: rule.id,
          channel: rule.channel,
          destination_masked: rule.destination_masked,
          headers_configured: rule.webhook? && rule.webhook_headers.present?,
          events: rule.events,
          enabled: rule.enabled,
          created_at: rule.created_at.iso8601,
          updated_at: rule.updated_at.iso8601
        }
      end

      def serialize_delivery(rule, result)
        {
          rule_id: rule.id,
          delivered: result.delivered,
          http_status: result.http_status,
          payload_kind: WebhookTestProbe::PAYLOAD_KIND,
          failure: result.failure
        }
      end
    end
  end
end
