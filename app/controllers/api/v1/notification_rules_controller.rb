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

      private

      def notification_rule_params
        permitted = params.require(:notification_rule).permit(:channel, :destination, :enabled, events: [], headers: {})
        headers = permitted.delete(:headers)
        permitted[:webhook_headers] = headers if headers
        permitted
      end

      def serialize_rule(rule)
        {
          id: rule.id,
          channel: rule.channel,
          destination_masked: masked_destination(rule),
          headers_configured: rule.webhook? && rule.webhook_headers.present?,
          events: rule.events,
          enabled: rule.enabled,
          created_at: rule.created_at.iso8601,
          updated_at: rule.updated_at.iso8601
        }
      end

      def masked_destination(rule)
        if rule.webhook?
          mask_webhook_url(rule.destination)
        else
          mask_email(rule.destination)
        end
      end

      def mask_webhook_url(destination)
        uri = URI.parse(destination)
        return "[masked]" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        "#{uri.scheme}://#{uri.host}/..."
      rescue URI::InvalidURIError
        "[masked]"
      end

      def mask_email(destination)
        local, domain = destination.to_s.split("@", 2)
        return "[masked]" if local.blank? || domain.blank?

        "#{local.first}***@#{domain}"
      end
    end
  end
end
