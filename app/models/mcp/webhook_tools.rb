# frozen_string_literal: true

module Mcp
  class WebhookTools
    SECRET_KEYS = %w[destination url headers webhook_headers].freeze

    def self.descriptors
      [
        {
          "name" => "oopsie_webhook_setup",
          "description" => "Ensure a webhook notification rule exists for an Oopsie project. Idempotent on the exact destination, headers, events, and enabled flag. Secrets are sent once and never returned. Then call oopsie_webhook_test with the returned id.",
          "inputSchema" => {
            "type" => "object",
            "required" => [ "url" ],
            "additionalProperties" => false,
            "properties" => {
              "project" => { "type" => "string", "description" => "Project name or id. Required with a user API key." },
              "url" => { "type" => "string", "description" => "Webhook URL. Never echoed back." },
              "headers" => {
                "type" => "object",
                "additionalProperties" => { "type" => "string" }
              },
              "events" => {
                "type" => "array",
                "items" => { "enum" => [ "new_error", "regression" ] }
              },
              "enabled" => { "type" => "boolean" }
            }
          }
        },
        {
          "name" => "oopsie_webhook_test",
          "description" => "Send a connectivity probe (event=test) to a stored webhook rule. Uses the destination and headers already saved on the server. A failed receiver is a structured result, not a protocol error.",
          "inputSchema" => {
            "type" => "object",
            "required" => [ "rule_id" ],
            "additionalProperties" => false,
            "properties" => {
              "project" => { "type" => "string" },
              "rule_id" => { "type" => "integer", "minimum" => 1 }
            }
          }
        },
        {
          "name" => "oopsie_webhook_list",
          "description" => "List webhook notification rules for the scoped project. Destinations are masked; header values are never returned.",
          "inputSchema" => {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "project" => { "type" => "string" }
            }
          }
        }
      ]
    end

    def self.call(name, arguments, project:, user:, project_header: nil)
      new(project: project, user: user, project_header: project_header).call(name, arguments)
    end

    def initialize(project:, user:, project_header: nil)
      @current_project = project
      @user = user
      @project_header = project_header
    end

    def call(name, arguments)
      arguments = {} unless arguments.is_a?(Hash)

      case name
      when "oopsie_webhook_setup" then setup(arguments)
      when "oopsie_webhook_test" then test(arguments)
      when "oopsie_webhook_list" then list(arguments)
      else tool_error("Unknown tool: #{name}")
      end
    end

    private

    def setup(arguments)
      url = arguments["url"].to_s
      return tool_error("url is required.") if url.blank?
      return tool_error("url must be an HTTP or HTTPS URL.") unless url.match?(/\Ahttps?:\/\//)

      project, error = resolve_project(arguments)
      return tool_error(error) if error

      result = WebhookRuleSetup.call(
        project: project,
        attributes: {
          destination: url,
          headers: arguments["headers"].is_a?(Hash) ? arguments["headers"] : {},
          events: arguments["events"].is_a?(Array) ? arguments["events"] : NotificationRule::SUPPORTED_EVENTS,
          enabled: arguments.key?("enabled") ? arguments["enabled"] : true
        }
      )
      return tool_error(validation_message(result.errors)) unless result.ok?

      payload = {
        "created" => result.created,
        "notification_rule" => serialize_rule(result.rule)
      }
      {
        "content" => [ { "type" => "text", "text" => setup_text(payload) } ],
        "structuredContent" => sanitize(payload),
        "isError" => false
      }
    end

    def test(arguments)
      rule_id = arguments["rule_id"].to_i
      return tool_error("rule_id is required.") if rule_id < 1

      project, error = resolve_project(arguments)
      return tool_error(error) if error

      rule = project.notification_rules.find_by(id: rule_id)
      return tool_error("Webhook rule not found.") unless rule
      return tool_error("Rule must be a webhook.") unless rule.webhook?

      result = WebhookTestProbe.call(project: project, rule: rule)
      delivery = sanitize(serialize_delivery(rule, result))
      text = if result.delivered
        "Webhook rule ##{rule.id} delivered (HTTP #{result.http_status})."
      else
        "Webhook rule ##{rule.id} did not deliver: #{result.failure&.fetch("message", "unknown error")}."
      end

      {
        "content" => [ { "type" => "text", "text" => text } ],
        "structuredContent" => { "delivery" => delivery },
        "isError" => false
      }
    end

    def list(arguments)
      project, error = resolve_project(arguments)
      return tool_error(error) if error

      webhooks = project.notification_rules.webhook.order(:created_at).map { |rule| sanitize(serialize_rule(rule)) }
      {
        "content" => [ { "type" => "text", "text" => "Found #{webhooks.length} webhook rule(s)." } ],
        "structuredContent" => { "webhooks" => webhooks },
        "isError" => false
      }
    end

    def resolve_project(arguments)
      return [ @current_project, nil ] if @current_project

      identifier = arguments["project"].presence || @project_header.presence
      return [ nil, "Pass project (name or id) when using a user API key." ] if identifier.blank?

      project = if identifier.to_s.match?(/\A\d+\z/)
        Project.find_by(id: identifier)
      else
        Project.find_by(name: identifier)
      end

      return [ nil, "Project not found." ] unless project

      [ project, nil ]
    end

    def serialize_rule(rule)
      {
        "id" => rule.id,
        "channel" => rule.channel,
        "destination_masked" => rule.destination_masked,
        "headers_configured" => rule.webhook? && rule.webhook_headers.present?,
        "events" => rule.events,
        "enabled" => rule.enabled
      }
    end

    def serialize_delivery(rule, result)
      {
        "rule_id" => rule.id,
        "delivered" => result.delivered,
        "http_status" => result.http_status,
        "payload_kind" => WebhookTestProbe::PAYLOAD_KIND,
        "failure" => result.failure
      }
    end

    def setup_text(payload)
      rule = payload["notification_rule"] || {}
      verb = payload["created"] ? "created" : "reused"
      "Webhook rule ##{rule["id"]} #{verb} (#{rule["destination_masked"]})."
    end

    def validation_message(errors)
      details = Array(errors).flat_map do |field, messages|
        Array(messages).map { |message| "#{field} #{message}" }
      end
      details.presence&.join(", ") || "Validation failed."
    end

    def sanitize(value)
      case value
      when Array then value.map { |item| sanitize(item) }
      when Hash
        value.each_with_object({}) do |(key, item), acc|
          next if SECRET_KEYS.include?(key.to_s)

          acc[key] = sanitize(item)
        end
      else
        value
      end
    end

    def tool_error(message)
      {
        "content" => [ { "type" => "text", "text" => message } ],
        "isError" => true
      }
    end
  end
end
