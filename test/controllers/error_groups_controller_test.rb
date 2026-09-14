require "test_helper"

class ErrorGroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @project = projects(:myapp)
    @error_group = error_groups(:nomethoderror)
  end

  test "shows error group detail page" do
    get project_error_group_url(@project, @error_group)
    assert_response :success
    assert_select "h1", /NoMethodError/
  end

  test "shows workflow state controls" do
    get project_error_group_url(@project, @error_group)
    assert_response :success
    assert_select ".badge", text: /untriaged/i
    assert_select "form[action=?]", workflow_state_project_error_group_path(@project, @error_group)
    assert_select "form[action=?]", project_error_group_notes_path(@project, @error_group)
  end

  test "shows a send notification control" do
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    begin
      get project_error_group_url(@project, @error_group)
      assert_response :success
      assert_select "form[action=?][method=?]", send_notification_project_error_group_path(@project, @error_group), "post" do
        assert_select "input[name='authenticity_token']"
        assert_select "button", text: /Send notification/i
      end
    ensure
      ActionController::Base.allow_forgery_protection = original_forgery_protection
    end
  end

  test "queues a manual notification for the latest occurrence" do
    assert_enqueued_with(
      job: NotifyJob,
      args: [ { error_group_id: @error_group.id, occurrence_id: occurrences(:first).id, manual: true } ]
    ) do
      post send_notification_project_error_group_url(@project, @error_group)
    end

    assert_redirected_to project_error_group_path(@project, @error_group)
    assert_match(/queued/i, flash[:notice])
  end

  test "shows backtrace from latest occurrence" do
    get project_error_group_url(@project, @error_group)
    assert_response :success
    assert_select ".backtrace-frame"
  end

  test "shows occurrence timeline" do
    get project_error_group_url(@project, @error_group)
    assert_response :success
    assert_select ".error-table tbody tr"
  end

  test "shows stats (count, first seen, last seen)" do
    get project_error_group_url(@project, @error_group)
    assert_select ".stat-value", /3/  # occurrences_count
    assert_select ".stat-label", /Total occurrences/
  end

  test "resolves an error group" do
    assert_difference "ErrorGroupNote.status_change.count", 1 do
      patch resolve_project_error_group_url(@project, @error_group)
    end
    assert_redirected_to project_error_group_path(@project, @error_group)
    assert_equal "resolved", @error_group.reload.status
  end

  test "ignores an error group" do
    assert_difference "ErrorGroupNote.status_change.count", 1 do
      patch ignore_project_error_group_url(@project, @error_group)
    end
    assert_redirected_to project_error_group_path(@project, @error_group)
    assert_equal "ignored", @error_group.reload.status
  end

  test "unresolves a resolved error group" do
    @error_group.resolved!
    assert_difference "ErrorGroupNote.status_change.count", 1 do
      patch unresolve_project_error_group_url(@project, @error_group)
    end
    assert_redirected_to project_error_group_path(@project, @error_group)
    assert_equal "unresolved", @error_group.reload.status
  end

  test "updates workflow state without resolving the group" do
    assert_difference "ErrorGroupNote.workflow_state_change.count", 1 do
      patch workflow_state_project_error_group_url(@project, @error_group),
        params: { workflow_state: "looking", note: "Checking stack trace." }
    end

    assert_redirected_to project_error_group_path(@project, @error_group)
    @error_group.reload
    note = @error_group.error_group_notes.workflow_state_change.last

    assert_equal "unresolved", @error_group.status
    assert_equal "looking", @error_group.workflow_state
    assert_equal "Checking stack trace.", note.body
    assert_equal users(:one).email_address, note.actor_label
  end

  test "adds investigation note" do
    assert_difference "ErrorGroupNote.note.count", 1 do
      post project_error_group_notes_url(@project, @error_group),
        params: { error_group_note: { body: "Looks tied to nil user." } }
    end

    assert_redirected_to project_error_group_path(@project, @error_group)
    note = @error_group.error_group_notes.note.last
    assert_equal "Looks tied to nil user.", note.body
    assert_equal "web", note.source
  end

  test "shows recent activity" do
    @error_group.add_note!("Visible activity", actor: users(:one), source: "test")

    get project_error_group_url(@project, @error_group)
    assert_response :success
    assert_select ".activity-list", text: /Visible activity/
  end

  test "shows context and server info" do
    get project_error_group_url(@project, @error_group)
    assert_select ".context-json"
  end

  test "links back to project" do
    get project_error_group_url(@project, @error_group)
    assert_select "a[href=?]", project_path(@project), text: @project.name
  end
end
