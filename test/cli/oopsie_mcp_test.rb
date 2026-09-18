require "test_helper"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"

load Rails.root.join("cli/oopsie-mcp").to_s

class OopsieMcpTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("oopsie-mcp-test")
    @bin_dir = File.join(@tmpdir, "bin")
    FileUtils.mkdir_p(@bin_dir)
    File.write(File.join(@bin_dir, "oopsie"), fake_oopsie_script)
    FileUtils.chmod(0o755, File.join(@bin_dir, "oopsie"))
    @original_oopsie_bin = ENV["OOPSIE_BIN"]
    ENV["OOPSIE_BIN"] = File.join(@bin_dir, "oopsie")
  end

  teardown do
    if @original_oopsie_bin
      ENV["OOPSIE_BIN"] = @original_oopsie_bin
    else
      ENV.delete("OOPSIE_BIN")
    end
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  test "lists webhook tools" do
    result = rpc("tools/list")

    names = result.fetch("tools").map { |tool| tool["name"] }
    assert_equal %w[oopsie_webhook_setup oopsie_webhook_test oopsie_webhook_list], names
  end

  test "setup pipes the url on stdin and never returns it" do
    result = rpc(
      "tools/call",
      name: "oopsie_webhook_setup",
      arguments: {
        "url" => "https://hooks.example.com/secret-path",
        "headers" => { "Authorization" => "Bearer tok" },
        "project" => "checkout"
      }
    )

    assert_equal false, result["isError"]
    refute_includes JSON.generate(result), "secret-path"
    refute_includes JSON.generate(result), "Bearer tok"
    assert_equal 12, result.dig("structuredContent", "notification_rule", "id")
    stdin = File.read(File.join(@tmpdir, "last-stdin.json"))
    assert_equal "https://hooks.example.com/secret-path", JSON.parse(stdin)["url"]
    argv = JSON.parse(File.read(File.join(@tmpdir, "last-argv.json")))
    refute_includes argv.join(" "), "secret-path"
    assert_includes argv, "--project"
    assert_includes argv, "checkout"
  end

  test "list strips destination and header values" do
    result = rpc("tools/call", name: "oopsie_webhook_list", arguments: { "project" => "checkout" })

    assert_equal false, result["isError"]
    webhooks = result.dig("structuredContent", "webhooks")
    assert_equal 12, webhooks.dig(0, "id")
    assert_equal "https://hooks.example.com/...", webhooks.dig(0, "destination_masked")
    refute webhooks.dig(0)&.key?("destination")
    refute webhooks.dig(0)&.key?("headers")
    refute_includes JSON.generate(result), "secret-path"
    refute_includes JSON.generate(result), "Bearer tok"
  end

  test "test reports a failed delivery without isError" do
    File.write(File.join(@tmpdir, "mode"), "failed-test")
    result = rpc("tools/call", name: "oopsie_webhook_test", arguments: { "rule_id" => 12 })

    assert_equal false, result["isError"]
    assert_equal false, result.dig("structuredContent", "delivery", "delivered")
    assert_equal "http_status", result.dig("structuredContent", "delivery", "failure", "kind")
  end

  private

  def rpc(method, **params)
    input = StringIO.new("#{JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params })}\n")
    output = StringIO.new
    OopsieMcp::Server.new(
      cli: OopsieMcp::Cli.new(bin: File.join(@bin_dir, "oopsie")),
      input: input,
      output: output
    ).run
    JSON.parse(output.string.lines.last)["result"]
  end

  def fake_oopsie_script
    dir = @tmpdir
    <<~RUBY
      #!/usr/bin/env ruby
      require "json"

      File.write(#{dir.dump} + "/last-argv.json", JSON.generate(ARGV))
      File.write(#{dir.dump} + "/last-stdin.json", $stdin.read)

      mode = File.exist?(#{dir.dump} + "/mode") ? File.read(#{dir.dump} + "/mode").strip : "ok"

      if ARGV.include?("version")
        puts JSON.generate(protocol_version: 1, ok: true, result: { version: "0.6.0", schema: 1 })
      elsif ARGV.include?("setup")
        puts JSON.generate(
          protocol_version: 1,
          ok: true,
          result: {
            created: true,
            notification_rule: {
              id: 12,
              channel: "webhook",
              destination_masked: "https://hooks.example.com/...",
              headers_configured: true,
              events: ["new_error", "regression"],
              enabled: true
            }
          }
        )
      elsif ARGV.include?("test") && mode == "failed-test"
        puts JSON.generate(
          protocol_version: 1,
          ok: true,
          result: {
            delivery: {
              rule_id: 12,
              delivered: false,
              http_status: 401,
              payload_kind: "connectivity_probe",
              failure: { kind: "http_status", message: "The endpoint returned HTTP 401." }
            }
          }
        )
      elsif ARGV.include?("test")
        puts JSON.generate(
          protocol_version: 1,
          ok: true,
          result: {
            delivery: {
              rule_id: 12,
              delivered: true,
              http_status: 204,
              payload_kind: "connectivity_probe",
              failure: nil
            }
          }
        )
      else
        puts JSON.generate(
          protocol_version: 1,
          ok: true,
          result: {
            webhooks: [
              {
                id: 12,
                channel: "webhook",
                destination: "https://hooks.example.com/secret-path",
                destination_masked: "https://hooks.example.com/...",
                headers: { "Authorization" => "Bearer tok" },
                headers_configured: true
              }
            ]
          }
        )
      end
    RUBY
  end
end
