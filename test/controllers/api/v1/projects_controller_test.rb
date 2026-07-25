require "test_helper"

class Api::V1::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:myapp)
    @headers = { "Authorization" => "Bearer #{@project.api_key}", "Content-Type" => "application/json" }
    @user = users(:one)
    @user_headers = { "Authorization" => "Bearer #{@user.api_key}", "Content-Type" => "application/json" }
  end

  test "shows project info" do
    get api_v1_project_url, headers: @headers
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal @project.name, json["name"]
    assert_equal @project.id, json["id"]
    assert json.key?("error_groups_count")
    assert json.key?("unresolved_count")
    assert json.key?("created_at")
    assert_equal "active", json["status"]
    assert_nil json["disabled_at"]
    assert_equal true, json["accepts_ingest"]
    assert_not json.key?("api_key")
  end

  test "user key lists all projects with status fields but without project keys" do
    @project.disable!

    get api_v1_project_url, headers: @user_headers
    assert_response :success

    json = JSON.parse(response.body)
    project_json = json["projects"].detect { |project| project["id"] == @project.id }

    assert project_json
    assert_equal "disabled", project_json["status"]
    assert_equal false, project_json["accepts_ingest"]
    assert project_json["disabled_at"].present?
    assert_not project_json.key?("api_key")
  end

  test "user key creates project and returns project key" do
    assert_difference "Project.count", 1 do
      post "/api/v1/projects",
        params: { project: { name: "Agent Created App" } }.to_json,
        headers: @user_headers
    end

    assert_response :created
    json = JSON.parse(response.body)
    project_json = json["project"]
    project = Project.find(project_json["id"])

    assert_equal "Agent Created App", project.name
    assert_equal true, json["created"]
    assert_equal project.api_key, project_json["api_key"]
    assert_equal "active", project_json["status"]
    assert_equal true, project_json["accepts_ingest"]
  end

  test "user key can idempotently reuse one existing project by name" do
    post "/api/v1/projects",
      params: { project: { name: @project.name }, if_missing: true }.to_json,
      headers: @user_headers

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal false, json["created"]
    assert_equal @project.id, json.dig("project", "id")
    assert_equal @project.api_key, json.dig("project", "api_key")
  end

  test "create maps unique index race to idempotent existing project response" do
    original_create = Project.method(:create!)
    Project.define_singleton_method(:create!) do |*_args, **_kwargs|
      raise ActiveRecord::RecordNotUnique.new("projects.name")
    end

    begin
      post "/api/v1/projects",
        params: { project: { name: @project.name }, if_missing: true }.to_json,
        headers: @user_headers
    ensure
      Project.define_singleton_method(:create!, original_create)
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal false, json["created"]
    assert_equal @project.id, json.dig("project", "id")
    assert_equal @project.api_key, json.dig("project", "api_key")
  end

  test "create rejects duplicate project name without if missing" do
    assert_no_difference "Project.count" do
      post "/api/v1/projects",
        params: { project: { name: @project.name } }.to_json,
        headers: @user_headers
    end

    assert_response :conflict
    json = JSON.parse(response.body)
    assert_equal "Project name already exists", json["error"]
    assert_includes json["matching_project_ids"], @project.id
  end

  test "user key renames project" do
    patch "/api/v1/projects/#{@project.id}",
      params: { project: { name: "Renamed App" } }.to_json,
      headers: @user_headers

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "Renamed App", json.dig("project", "name")
    assert_not json["project"].key?("api_key")
    assert_equal "Renamed App", @project.reload.name
  end

  test "rename rejects duplicate project name" do
    other_project = projects(:otherapp)

    patch "/api/v1/projects/#{@project.id}",
      params: { project: { name: other_project.name } }.to_json,
      headers: @user_headers

    assert_response :conflict
    json = JSON.parse(response.body)
    assert_equal "Project name already exists", json["error"]
    assert_equal other_project.id, json.dig("project", "id")
  end

  test "user key disables and enables project" do
    patch "/api/v1/projects/#{@project.id}/disable", headers: @user_headers
    assert_response :success

    @project.reload
    assert_equal "disabled", @project.status
    assert @project.disabled_at.present?
    assert_equal false, JSON.parse(response.body).dig("project", "accepts_ingest")

    patch "/api/v1/projects/#{@project.id}/enable", headers: @user_headers
    assert_response :success

    @project.reload
    assert_equal "active", @project.status
    assert_nil @project.disabled_at
    assert_equal true, JSON.parse(response.body).dig("project", "accepts_ingest")
  end

  test "project key cannot create update disable or enable projects" do
    assert_no_difference "Project.count" do
      post "/api/v1/projects",
        params: { project: { name: "Forbidden App" } }.to_json,
        headers: @headers
    end
    assert_response :forbidden
    assert_equal "User API key required", JSON.parse(response.body)["error"]

    patch "/api/v1/projects/#{@project.id}",
      params: { project: { name: "Forbidden Rename" } }.to_json,
      headers: @headers
    assert_response :forbidden

    patch "/api/v1/projects/#{@project.id}/disable", headers: @headers
    assert_response :forbidden
    assert_equal "active", @project.reload.status

    patch "/api/v1/projects/#{@project.id}/enable", headers: @headers
    assert_response :forbidden
  end

  test "returns 401 without auth" do
    get api_v1_project_url
    assert_response :unauthorized
  end

  test "returns 401 with invalid key" do
    get api_v1_project_url, headers: { "Authorization" => "Bearer invalid", "Content-Type" => "application/json" }
    assert_response :unauthorized
  end
end
