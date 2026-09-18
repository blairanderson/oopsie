# frozen_string_literal: true

require "net/http"
require "openssl"

class WebhookDelivery
  class TimeoutError < StandardError; end

  Result = Data.define(:delivered, :http_status, :failure) do
    def retryable?
      failure&.dig("kind") == "timeout"
    end
  end

  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 10

  def self.call(url:, headers: {}, payload:)
    uri = URI.parse(url)
    unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      return failure("invalid_url", "The destination must be an HTTP or HTTPS URL.")
    end

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Post.new(uri.request_uri.presence || "/")
    request["Content-Type"] = "application/json"
    headers.each { |name, value| request[name] = value }
    request.body = payload.to_json

    response = http.request(request)
    status = response.code.to_i

    if response.is_a?(Net::HTTPSuccess)
      Result.new(delivered: true, http_status: status, failure: nil)
    else
      Result.new(
        delivered: false,
        http_status: status,
        failure: { "kind" => "http_status", "message" => "The endpoint returned HTTP #{status}." }
      )
    end
  rescue URI::InvalidURIError
    failure("invalid_url", "The destination is not a valid URL.")
  rescue Net::OpenTimeout, Net::ReadTimeout
    failure("timeout", "The endpoint did not respond before the timeout.")
  rescue OpenSSL::SSL::SSLError
    failure("tls", "The TLS handshake failed.")
  rescue SocketError
    failure("dns", "The hostname could not be resolved.")
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ECONNRESET
    failure("connection", "The endpoint could not be reached.")
  rescue StandardError
    failure("connection", "The webhook could not be delivered.")
  end

  def self.failure(kind, message)
    Result.new(
      delivered: false,
      http_status: nil,
      failure: { "kind" => kind, "message" => message }
    )
  end
  private_class_method :failure
end
