# frozen_string_literal: true

module Mcp
  class Protocol
    PROTOCOL_VERSIONS = %w[2025-03-26 2025-06-18 2025-11-25].freeze
    PREFERRED_PROTOCOL = "2025-06-18"
    SERVER_VERSION = "0.6.0"

    Outcome = Data.define(:status, :body) do
      def accepted?
        status == 202
      end
    end

    def self.call(message, project:, user:, project_header: nil)
      new(project: project, user: user, project_header: project_header).call(message)
    end

    def initialize(project:, user:, project_header: nil)
      @project = project
      @user = user
      @project_header = project_header
    end

    def call(message)
      return rpc_error(nil, -32700, "Parse error") unless message.is_a?(Hash)
      return accepted if message["method"].to_s.start_with?("notifications/") && message["id"].nil?

      method = message["method"]
      id = message["id"]
      params = message["params"] || {}
      params = {} unless params.is_a?(Hash)

      case method
      when "initialize"
        rpc_result(id, initialize_result(params))
      when "ping"
        rpc_result(id, {})
      when "tools/list"
        rpc_result(id, { "tools" => Mcp::WebhookTools.descriptors })
      when "tools/call"
        rpc_result(id, Mcp::WebhookTools.call(
          params["name"],
          params["arguments"] || {},
          project: @project,
          user: @user,
          project_header: @project_header
        ))
      else
        return rpc_error(id, -32600, "Invalid Request") if method.blank?

        rpc_error(id, -32601, "Method not found")
      end
    end

    private

    def initialize_result(params)
      requested = params["protocolVersion"].to_s
      version = PROTOCOL_VERSIONS.include?(requested) ? requested : PREFERRED_PROTOCOL

      {
        "protocolVersion" => version,
        "capabilities" => { "tools" => { "listChanged" => false } },
        "serverInfo" => { "name" => "oopsie", "version" => SERVER_VERSION },
        "instructions" => "Set up and test Oopsie webhook notification rules. Pass project when using a user API key. Destinations and header values are never returned."
      }
    end

    def accepted
      Outcome.new(status: 202, body: nil)
    end

    def rpc_result(id, result)
      return accepted if id.nil?

      Outcome.new(status: 200, body: { "jsonrpc" => "2.0", "id" => id, "result" => result })
    end

    def rpc_error(id, code, message)
      Outcome.new(
        status: 200,
        body: { "jsonrpc" => "2.0", "id" => id, "error" => { "code" => code, "message" => message } }
      )
    end
  end
end
