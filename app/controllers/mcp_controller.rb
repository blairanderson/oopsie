# frozen_string_literal: true

class McpController < Api::V1::BaseController
  def handle
    if request.get? || request.delete?
      head :method_not_allowed
      return
    end

    message = parse_message
    unless message
      render json: { jsonrpc: "2.0", id: nil, error: { code: -32700, message: "Parse error" } }, status: :bad_request
      return
    end

    outcome = Mcp::Protocol.call(
      message,
      project: @project,
      user: @user,
      project_header: request.headers["X-Project-Id"]
    )

    if outcome.accepted?
      head :accepted
    else
      render json: outcome.body, status: outcome.status
    end
  end

  private

  def parse_message
    body = request.raw_post
    return {} if body.blank?

    JSON.parse(body)
  rescue JSON::ParserError
    nil
  end

  def authenticate!
    super
    return if @project || @user

    response.set_header("WWW-Authenticate", 'Bearer realm="oopsie"')
  end
end
