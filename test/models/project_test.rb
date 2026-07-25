require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "valid project" do
    project = Project.new(name: "TestApp")
    assert project.valid?
    assert project.api_key.present?, "should auto-generate api_key"
  end

  test "requires name" do
    project = Project.new(name: nil)
    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"
  end

  test "requires unique name" do
    Project.create!(name: "UniqueApp")

    duplicate = Project.new(name: "UniqueApp")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "database enforces unique names for concurrent creates" do
    Project.create!(name: "RaceApp")

    assert_raises ActiveRecord::RecordNotUnique do
      Project.insert_all!([
        {
          name: "RaceApp",
          api_key: SecureRandom.hex(32),
          status: Project.statuses[:active],
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    end
  end

  test "generates unique api_key on create" do
    p1 = Project.create!(name: "App1")
    p2 = Project.create!(name: "App2")
    assert_not_equal p1.api_key, p2.api_key
  end

  test "does not overwrite provided api_key" do
    project = Project.new(name: "TestApp", api_key: "custom_key")
    assert_equal "custom_key", project.api_key
  end

  test "api_key must be unique" do
    Project.create!(name: "App1", api_key: "same_key")
    duplicate = Project.new(name: "App2", api_key: "same_key")
    assert_not duplicate.valid?
  end

  test "projects are active by default and accept ingest" do
    project = Project.create!(name: "App1")

    assert_equal "active", project.status
    assert_nil project.disabled_at
    assert project.accepts_ingest?
  end

  test "disable marks project disabled with timestamp" do
    project = projects(:myapp)

    travel_to Time.zone.parse("2026-07-25 06:00:00 UTC") do
      project.disable!
    end

    project.reload
    assert_equal "disabled", project.status
    assert_equal Time.zone.parse("2026-07-25 06:00:00 UTC"), project.disabled_at
    assert_not project.accepts_ingest?
  end

  test "enable reactivates project and clears disabled timestamp" do
    project = projects(:myapp)
    project.disable!

    project.enable!

    project.reload
    assert_equal "active", project.status
    assert_nil project.disabled_at
    assert project.accepts_ingest?
  end

  test "destroying project destroys error_groups" do
    project = projects(:myapp)
    assert_difference "ErrorGroup.count", -project.error_groups.count do
      project.destroy
    end
  end
end
