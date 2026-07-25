require "test_helper"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

class OopsieCliTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("oopsie-cli-test")
    @config_dir = File.join(@tmpdir, "config")
    @bin_dir = File.join(@tmpdir, "bin")
    @curl_log = File.join(@tmpdir, "curl.log")
    FileUtils.mkdir_p(@config_dir)
    FileUtils.mkdir_p(@bin_dir)

    File.write(File.join(@config_dir, "config.json"), JSON.generate(
      connections: {
        prod: {
          server: "http://oopsie.test",
          key: "user-key",
          project: { id: 7, name: "MyApp" }
        }
      },
      default: "prod"
    ))

    File.write(File.join(@bin_dir, "curl"), fake_curl_script)
    FileUtils.chmod(0o755, File.join(@bin_dir, "curl"))
  end

  teardown do
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  test "state command patches workflow state with note and provenance" do
    stdout, stderr, status = run_cli("state", "42", "in_progress", "--note", "Investigating cache miss.")

    assert status.success?, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    assert_includes stdout, "Set error group #42 workflow state to in_progress."

    args = curl_calls.last
    body = JSON.parse(value_after(args, "-d"))

    assert_equal "PATCH", value_after(args, "-X")
    assert_equal "http://oopsie.test/api/v1/error_groups/42/workflow_state", args.last
    assert_equal "in_progress", body["workflow_state"]
    assert_equal "Investigating cache miss.", body["note"]
    assert_includes headers_from(args), "X-Project-Id: 7"
    assert_includes headers_from(args), "X-Oopsie-Client: cli/oopsie 0.5.0"
  end

  test "projects command displays project status" do
    stdout, stderr, status = run_cli("projects")

    assert status.success?, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    assert_includes stdout, "PROJECTS"
    assert_includes stdout, "MyApp"
    assert_includes stdout, "[ACTIVE]"
    assert_includes stdout, "PausedApp"
    assert_includes stdout, "[DISABLED]"
  end

  test "help documents project administration permissions" do
    stdout, stderr, status = run_cli("help")

    assert status.success?, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    assert_includes stdout, "Project administration (User API key required)"
    assert_includes stdout, "oopsie project create <name> [--if-missing]"
    assert_includes stdout, "oopsie project disable <project>"
    assert_includes stdout, "User key"
    assert_includes stdout, "create, rename, disable, and enable projects"
  end

  test "project create posts name and if missing flag and prints project key" do
    stdout, stderr, status = run_cli("project", "create", "Agent App", "--if-missing")

    assert status.success?, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    assert_includes stdout, "Created project #9."
    assert_includes stdout, "Project key:     project-key-new"
    assert_includes stdout, "OOPSIE_API_KEY=project-key-new"

    args = curl_calls.last
    body = JSON.parse(value_after(args, "-d"))

    assert_equal "POST", value_after(args, "-X")
    assert_equal "http://oopsie.test/api/v1/projects", args.last
    assert_equal "Agent App", body.dig("project", "name")
    assert_equal true, body["if_missing"]
  end

  test "project update patches new name" do
    stdout, stderr, status = run_cli("project", "update", "7", "--name", "Renamed App")

    assert status.success?, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    assert_includes stdout, "Updated project #7."
    assert_includes stdout, "Renamed App"

    args = curl_calls.last
    body = JSON.parse(value_after(args, "-d"))

    assert_equal "PATCH", value_after(args, "-X")
    assert_equal "http://oopsie.test/api/v1/projects/7", args.last
    assert_equal "Renamed App", body.dig("project", "name")
  end

  test "project disable and enable patch project admin endpoints" do
    stdout, stderr, status = run_cli("project", "disable", "7")

    assert status.success?, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    assert_includes stdout, "Disabled project #7."
    assert_includes stdout, "[DISABLED]"
    assert_includes stdout, "Accepts ingest:  no"
    assert_equal "PATCH", value_after(curl_calls.last, "-X")
    assert_equal "http://oopsie.test/api/v1/projects/7/disable", curl_calls.last.last

    stdout, stderr, status = run_cli("project", "enable", "7")

    assert status.success?, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    assert_includes stdout, "Enabled project #7."
    assert_includes stdout, "[ACTIVE]"
    assert_includes stdout, "Accepts ingest:  yes"
    assert_equal "PATCH", value_after(curl_calls.last, "-X")
    assert_equal "http://oopsie.test/api/v1/projects/7/enable", curl_calls.last.last
  end

  test "project admin command surfaces server forbidden error" do
    stdout, stderr, status = run_cli("project", "create", "Forbidden")

    assert_not status.success?, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    assert_empty stdout
    assert_includes stderr, "User API key required"
  end

  test "project name resolution rejects ambiguous names" do
    stdout, stderr, status = run_cli("project", "disable", "DupApp")

    assert_not status.success?, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    assert_empty stdout
    assert_includes stderr, "Project name 'DupApp' is ambiguous"
    assert_equal "GET", value_after(curl_calls.last, "-X")
    assert_equal "http://oopsie.test/api/v1/project", curl_calls.last.last
  end

  test "note command posts plain note body" do
    stdout, stderr, status = run_cli("note", "42", "--body", "Confirmed nil user.")

    assert status.success?, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    assert_includes stdout, "Added note to error group #42."

    args = curl_calls.last
    body = JSON.parse(value_after(args, "-d"))

    assert_equal "POST", value_after(args, "-X")
    assert_equal "http://oopsie.test/api/v1/error_groups/42/notes", args.last
    assert_equal "Confirmed nil user.", body["body"]
  end

  test "errors command filters by workflow state and displays it" do
    stdout, stderr, status = run_cli("errors", "--workflow-state", "blocked")

    assert status.success?, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    assert_includes stdout, "[BLOCKED]"
    assert_includes stdout, "NoMethodError"
    assert_includes curl_calls.last.last, "workflow_state=blocked"
  end

  test "resolve command accepts note evidence" do
    stdout, stderr, status = run_cli("resolve", "42", "--note", "Fixed in deploy.")

    assert status.success?, "stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    assert_includes stdout, "Resolved error group #42."

    args = curl_calls.last
    body = JSON.parse(value_after(args, "-d"))

    assert_equal "PATCH", value_after(args, "-X")
    assert_equal "http://oopsie.test/api/v1/error_groups/42/resolve", args.last
    assert_equal "Fixed in deploy.", body["note"]
  end

  private

  def run_cli(*args)
    env = {
      "OOPSIE_CONFIG_DIR" => @config_dir,
      "CURL_LOG" => @curl_log,
      "PATH" => "#{@bin_dir}:#{ENV.fetch('PATH')}"
    }

    Open3.capture3(env, Rails.root.join("cli/oopsie").to_s, *args)
  end

  def curl_calls
    File.readlines(@curl_log).map { |line| JSON.parse(line) }
  end

  def value_after(args, flag)
    index = args.index(flag)
    args.fetch(index + 1)
  end

  def headers_from(args)
    args.each_cons(2).filter_map { |flag, value| value if flag == "-H" }
  end

  def fake_curl_script
    <<~RUBY
      #!/usr/bin/env ruby
      require "json"

      File.open(ENV.fetch("CURL_LOG"), "a") { |file| file.puts(JSON.generate(ARGV)) }

      method = ARGV[ARGV.index("-X") + 1]
      url = ARGV.last
      request_body = if ARGV.include?("-d")
        JSON.parse(ARGV[ARGV.index("-d") + 1])
      else
        {}
      end

      response =
        if method == "POST" && url.end_with?("/api/v1/projects") && request_body.dig("project", "name") == "Forbidden"
          puts JSON.generate({ error: "User API key required" })
          puts "403"
          exit
        elsif method == "GET" && url.end_with?("/api/v1/project")
          {
            projects: [
              {
                id: 7,
                name: "MyApp",
                status: "active",
                disabled_at: nil,
                accepts_ingest: true,
                unresolved_count: 2,
                error_groups_count: 5,
                created_at: "2026-05-25T18:00:00Z"
              },
              {
                id: 8,
                name: "PausedApp",
                status: "disabled",
                disabled_at: "2026-07-25T06:00:00Z",
                accepts_ingest: false,
                unresolved_count: 0,
                error_groups_count: 1,
                created_at: "2026-05-25T18:00:00Z"
              },
              {
                id: 10,
                name: "DupApp",
                status: "active",
                accepts_ingest: true,
                unresolved_count: 0,
                error_groups_count: 0,
                created_at: "2026-05-25T18:00:00Z"
              },
              {
                id: 11,
                name: "DupApp",
                status: "active",
                accepts_ingest: true,
                unresolved_count: 0,
                error_groups_count: 0,
                created_at: "2026-05-25T18:00:00Z"
              }
            ]
          }
        elsif method == "POST" && url.end_with?("/api/v1/projects")
          {
            project: {
              id: 9,
              name: request_body.dig("project", "name"),
              status: "active",
              disabled_at: nil,
              accepts_ingest: true,
              error_groups_count: 0,
              unresolved_count: 0,
              created_at: "2026-07-25T06:00:00Z",
              api_key: "project-key-new"
            },
            created: true
          }
        elsif method == "PATCH" && url.end_with?("/api/v1/projects/7")
          {
            project: {
              id: 7,
              name: request_body.dig("project", "name"),
              status: "active",
              disabled_at: nil,
              accepts_ingest: true,
              error_groups_count: 5,
              unresolved_count: 2,
              created_at: "2026-05-25T18:00:00Z"
            }
          }
        elsif method == "PATCH" && url.end_with?("/api/v1/projects/7/disable")
          {
            project: {
              id: 7,
              name: "MyApp",
              status: "disabled",
              disabled_at: "2026-07-25T06:00:00Z",
              accepts_ingest: false,
              error_groups_count: 5,
              unresolved_count: 2,
              created_at: "2026-05-25T18:00:00Z"
            }
          }
        elsif method == "PATCH" && url.end_with?("/api/v1/projects/7/enable")
          {
            project: {
              id: 7,
              name: "MyApp",
              status: "active",
              disabled_at: nil,
              accepts_ingest: true,
              error_groups_count: 5,
              unresolved_count: 2,
              created_at: "2026-05-25T18:00:00Z"
            }
          }
        elsif method == "GET" && url.include?("/api/v1/error_groups?")
          {
            error_groups: [
              {
                id: 42,
                error_class: "NoMethodError",
                message: "undefined method",
                status: "unresolved",
                workflow_state: "blocked",
                occurrences_count: 3,
                first_seen_at: "2026-05-25T18:00:00Z",
                last_seen_at: "2026-05-25T19:00:00Z"
              }
            ],
            total: 1
          }
        elsif method == "POST" && url.end_with?("/notes")
          { note: { id: 9, kind: "note" }, error_group: { id: 42, workflow_state: "blocked" } }
        else
          { error_group: { id: 42, status: "unresolved", workflow_state: "in_progress" } }
        end

      puts JSON.generate(response)
      puts "200"
    RUBY
  end
end
