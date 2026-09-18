# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_18_000000) do
  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "last_seen_client"
    t.datetime "last_used_at"
    t.string "name", null: false
    t.integer "project_id"
    t.integer "requests_count", default: 0, null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["project_id", "name"], name: "index_active_project_api_tokens_on_name", unique: true, where: "revoked_at IS NULL AND project_id IS NOT NULL"
    t.index ["project_id"], name: "index_api_tokens_on_project_id"
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id", "name"], name: "index_active_user_api_tokens_on_name", unique: true, where: "revoked_at IS NULL AND user_id IS NOT NULL"
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "error_group_notes", force: :cascade do |t|
    t.string "actor_kind", default: "system", null: false
    t.string "actor_label", default: "system", null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "error_group_id", null: false
    t.string "from_value"
    t.integer "kind", default: 0, null: false
    t.string "source", default: "unknown", null: false
    t.string "to_value"
    t.datetime "updated_at", null: false
    t.index ["error_group_id", "created_at"], name: "index_error_group_notes_on_error_group_id_and_created_at"
    t.index ["error_group_id", "kind", "created_at"], name: "idx_on_error_group_id_kind_created_at_46fdc2d8ec"
    t.index ["error_group_id"], name: "index_error_group_notes_on_error_group_id"
  end

  create_table "error_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_class", null: false
    t.string "fingerprint", null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.string "message"
    t.integer "occurrences_count", default: 0, null: false
    t.integer "project_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "workflow_state", default: 0, null: false
    t.datetime "workflow_state_changed_at", null: false
    t.index ["project_id", "fingerprint"], name: "index_error_groups_on_project_id_and_fingerprint", unique: true
    t.index ["project_id", "status", "last_seen_at"], name: "index_error_groups_on_project_id_and_status_and_last_seen_at"
    t.index ["project_id", "workflow_state", "last_seen_at"], name: "index_error_groups_on_project_workflow_last_seen"
    t.index ["project_id"], name: "index_error_groups_on_project_id"
  end

  create_table "notification_rules", force: :cascade do |t|
    t.integer "channel", null: false
    t.datetime "created_at", null: false
    t.string "destination", null: false
    t.boolean "enabled", default: true, null: false
    t.json "events"
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.json "webhook_headers"
    t.index ["project_id"], name: "index_notification_rules_on_project_id"
  end

  create_table "occurrences", force: :cascade do |t|
    t.json "backtrace"
    t.json "causes"
    t.json "context"
    t.datetime "created_at", null: false
    t.string "environment"
    t.integer "error_group_id", null: false
    t.json "first_line"
    t.boolean "handled", default: false, null: false
    t.string "message"
    t.string "notifier_version"
    t.datetime "occurred_at", null: false
    t.json "server_info"
    t.datetime "updated_at", null: false
    t.index ["error_group_id", "occurred_at"], name: "index_occurrences_on_error_group_id_and_occurred_at"
    t.index ["error_group_id"], name: "index_occurrences_on_error_group_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "api_key", null: false
    t.datetime "created_at", null: false
    t.datetime "disabled_at"
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["api_key"], name: "index_projects_on_api_key", unique: true
    t.index ["name"], name: "index_projects_on_name", unique: true
    t.index ["status"], name: "index_projects_on_status"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "api_key", null: false
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key"], name: "index_users_on_api_key", unique: true
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "api_tokens", "projects"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "error_group_notes", "error_groups"
  add_foreign_key "error_groups", "projects"
  add_foreign_key "notification_rules", "projects"
  add_foreign_key "occurrences", "error_groups"
  add_foreign_key "sessions", "users"
end
