require "test_helper"

class WebhookDeliveryTest < ActiveSupport::TestCase
  class RecordingHttp
    attr_reader :last_request

    def initialize(response)
      @response = response
    end

    def use_ssl=(_value)
    end

    def open_timeout=(_value)
    end

    def read_timeout=(_value)
    end

    def request(request)
      @last_request = request
      @response
    end
  end

  test "preserves query strings on the request path" do
    http = RecordingHttp.new(Net::HTTPSuccess.new("1.1", "204", "No Content"))
    stub_net_http(http) do
      result = WebhookDelivery.call(
        url: "https://hooks.example.com/notify?token=secret",
        headers: { "Authorization" => "Bearer tok" },
        payload: { event: "test" }
      )
      assert result.delivered
      assert_equal 204, result.http_status
    end

    assert_includes [ "/notify?token=secret", "https://hooks.example.com/notify?token=secret" ], http.last_request.path
    assert_equal "Bearer tok", http.last_request["Authorization"]
  end

  test "maps non-2xx responses to a typed failure without echoing the URL" do
    http = RecordingHttp.new(Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized"))
    result = nil
    stub_net_http(http) do
      result = WebhookDelivery.call(
        url: "https://hooks.example.com/secret/path",
        payload: { event: "test" }
      )
    end

    assert_not result.delivered
    assert_equal 401, result.http_status
    assert_equal "http_status", result.failure["kind"]
    assert_equal "The endpoint returned HTTP 401.", result.failure["message"]
    assert_no_match(/secret/, result.failure["message"])
  end

  test "maps timeouts to a retryable failure" do
    http = Object.new
    def http.use_ssl=(_value); end
    def http.open_timeout=(_value); end
    def http.read_timeout=(_value); end
    def http.request(_request)
      raise Net::OpenTimeout, "execution expired"
    end

    result = stub_net_http(http) do
      WebhookDelivery.call(url: "https://hooks.example.com/notify", payload: { event: "test" })
    end

    assert_not result.delivered
    assert result.retryable?
    assert_equal "timeout", result.failure["kind"]
  end

  test "rejects non-http destinations" do
    result = WebhookDelivery.call(url: "ftp://example.com/hook", payload: {})

    assert_not result.delivered
    assert_nil result.http_status
    assert_equal "invalid_url", result.failure["kind"]
  end

  private

  def stub_net_http(http)
    original_http_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| http }
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original_http_new)
  end
end
