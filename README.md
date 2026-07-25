# Oopsie

Self-hosted exception tracking for solo and indie Rails developers. One app, one SQLite database, zero external dependencies.

Deploy Oopsie. Add one gem to your app. Never pay for error tracking again.

## What it does

- **Receives exceptions** via the ExceptionReporter webhook format
- **Groups them intelligently** by error class + stack frame (not just message)
- **Notifies you** via email or webhook when something new breaks
- **Tracks regressions** — resolved errors that come back get reopened automatically

## Quick Start

```bash
git clone https://github.com/theinventor/Oopsie.git
cd Oopsie
bin/setup --skip-server
```

This will:
1. Install dependencies
2. Create the SQLite database
3. Seed an admin user (credentials printed to stdout — save them)
4. Create a demo project with sample exceptions

Then start the server:

```bash
bin/dev
```

Visit [http://localhost:3000](http://localhost:3000) and log in with the credentials from setup.

## Stack

- Ruby 4.0.2 / Rails 8.1
- SQLite (WAL mode)
- Solid Queue (background jobs)
- Propshaft (assets)
- No Redis. No Postgres. No external services.

## API Keys

Oopsie has two kinds of API keys:

| Key type | Scope | Where to find it | Best for |
|----------|-------|------------------|----------|
| **Project key** | One project | Project → Settings | Reporting exceptions from an app |
| **User key** | All your projects | Account page | CLI, cross-project tooling, dashboards |

Both authenticate via `Authorization: Bearer <key>`. When you use a user key on a
project-scoped endpoint, pass the project as a `project_id` query param or
`X-Project-Id` header. User keys can also create, rename, disable, and re-enable
projects through the API and CLI. Project keys cannot administer projects, even
their own. Keys can be rotated from the UI — old keys invalidate immediately.

## Client Integration

Oopsie accepts the [ExceptionReporter](https://github.com/theinventor/exception_reporter) webhook payload. Use a **project key** for reporting from a client app:

```ruby
ExceptionReporter.configure do |config|
  config.add_webhook(
    "https://your-oopsie-instance.com/api/v1/exceptions",
    headers: { "Authorization" => "Bearer #{ENV['OOPSIE_API_KEY']}" }
  )
end
```

## CLI

A small bash client is included at `cli/oopsie` for managing exceptions from the terminal or from AI assistants. Requires `curl` and `jq`.

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/theinventor/Oopsie/main/cli/oopsie -o oopsie
chmod +x oopsie && sudo mv oopsie /usr/local/bin/

# Configure a connection (use your User API key from the Account page)
oopsie config add prod --server https://your-oopsie.com --key YOUR_USER_KEY

# Pin a default project for this connection (optional)
oopsie config set-project myapp

# Everyday use
oopsie whoami                     # what am I logged in as?
oopsie projects                   # list everything I can access
oopsie errors --status unresolved # what's broken?
oopsie show 42                    # full details + stack traces
oopsie state 42 looking --note "Checking recent deploys"
oopsie note 42 --body "Reproduced locally with account 123"
oopsie resolve 42                 # mark fixed

# Project admin (user key required)
oopsie project create "New App" --if-missing
oopsie project update 42 --name "Renamed App"
oopsie project disable 42         # stop new exception ingest
oopsie project enable 42          # resume exception ingest

# Notification rules
oopsie notifications --project myapp
printf '%s' "$OOPSIE_WEBHOOK_URL" | \
  oopsie notification create --project myapp --kind webhook --url-stdin --events error.created,error.reopened
```

Override the scope for any command with `-p/--project <name>` or the connection with `-c/--connection <name>`. Full help: `oopsie help`.

## API

### POST /api/v1/exceptions

Report an exception. Accepts a **project key** or a **user key** (with project context).
Disabled projects return `403` and do not create error groups or occurrences.

**Headers:**

```
Authorization: Bearer <api_key>
Content-Type: application/json
```

When using a user key, also pass `X-Project-Id: <id>` or `?project_id=<id>`.

**Payload:**

```json
{
  "notifier": "ExceptionReporter",
  "version": "1.0.0",
  "timestamp": "2026-04-04T14:23:45.892Z",
  "app": {
    "name": "MyApp",
    "environment": "production"
  },
  "error": {
    "class_name": "NoMethodError",
    "message": "undefined method 'downloads' for nil",
    "backtrace": [
      "app/controllers/designs_controller.rb:42:in 'show'",
      "actionpack (8.1.3) lib/action_controller/metal.rb:227:in 'dispatch'"
    ],
    "first_line": {
      "file": "app/controllers/designs_controller.rb",
      "line": 42,
      "method": "show"
    },
    "causes": [],
    "handled": false
  },
  "context": {
    "request": { "url": "/designs/1", "method": "GET" },
    "action": "DesignsController#show"
  },
  "server": {
    "hostname": "web-1",
    "pid": 12345,
    "ruby_version": "4.0.2",
    "rails_version": "8.1.3"
  }
}
```

**Response (201 Created):**

```json
{
  "id": 1,
  "group_id": 1,
  "is_new_group": true
}
```

**Error responses:**

| Status | Meaning |
|--------|---------|
| 400 | User key used without project context — pass `project_id` or `X-Project-Id` |
| 401 | Invalid or missing API key |
| 403 | Project is disabled and cannot accept new exceptions |
| 422 | Malformed payload (missing `error` or `error.class_name`) |
| 429 | Rate limit exceeded (100 requests/minute per key) |

### Project administration

Project administration requires a **user key**. The response to project creation
includes the new project's project key so an agent can immediately configure a
client app without visiting the web UI. Project names are unique; pass
`if_missing: true` when setup scripts should reuse one existing project with the
same name instead of failing with `409 Conflict`.

```bash
curl -X POST https://your-oopsie.com/api/v1/projects \
  -H 'Authorization: Bearer YOUR_USER_KEY' \
  -H 'Content-Type: application/json' \
  -d '{"project":{"name":"New App"},"if_missing":true}'
```

```json
{
  "project": {
    "id": 42,
    "name": "New App",
    "status": "active",
    "disabled_at": null,
    "accepts_ingest": true,
    "error_groups_count": 0,
    "unresolved_count": 0,
    "created_at": "2026-07-25T06:00:00Z",
    "api_key": "project_key_for_client_apps"
  },
  "created": true
}
```

### Other endpoints

Authenticated with a Bearer token. Project-scoped endpoints need a project context (implicit with a project key, explicit with a user key via `X-Project-Id` header or `project_id` param).

| Method | Path | Description |
|--------|------|-------------|
| `GET`    | `/api/v1/project` | Project summary with `status`, `disabled_at`, and `accepts_ingest` — single project with a project key, `{projects: [...]}` with a user key |
| `POST`   | `/api/v1/projects` | Create a project with a user key (`project.name`, optional `if_missing`) and return its project key |
| `PATCH`  | `/api/v1/projects/:id` | Rename a project with a user key (`project.name`) |
| `PATCH`  | `/api/v1/projects/:id/disable` | Disable new exception ingest for a project with a user key |
| `PATCH`  | `/api/v1/projects/:id/enable` | Re-enable exception ingest for a project with a user key |
| `GET`    | `/api/v1/notification_rules` | List notification destinations for the scoped project |
| `POST`   | `/api/v1/notification_rules` | Create a notification rule (`channel`, `destination`, optional `events`) |
| `GET`    | `/api/v1/error_groups` | List error groups (`?status=`, `?limit=`, `?offset=`) |
| `GET`    | `/api/v1/error_groups/:id` | Group details + recent occurrences |
| `PATCH`  | `/api/v1/error_groups/:id/workflow_state` | Set agent workflow state (`workflow_state`, optional `note`) |
| `POST`   | `/api/v1/error_groups/:id/notes` | Add an investigation note (`body`) |
| `PATCH`  | `/api/v1/error_groups/:id/resolve` | Mark resolved |
| `PATCH`  | `/api/v1/error_groups/:id/ignore` | Archive (ignore) |
| `PATCH`  | `/api/v1/error_groups/:id/unresolve` | Reopen |

### Agent triage workflow

Oopsie keeps lifecycle status and agent workflow state separate. Use
`unresolved`, `resolved`, and `ignored` only for the real error lifecycle.
Use workflow state for coordination:

| Workflow state | Use it when |
|----------------|-------------|
| `untriaged` | Nobody has started looking yet |
| `looking` | An agent is inspecting the group |
| `in_progress` | A fix is being implemented or verified |
| `blocked` | The group needs external input or cannot be acted on yet |
| `ready_to_resolve` | Evidence says the group can be resolved or ignored |

Agents should set a workflow state first, add notes with evidence, and only call
`resolve` or `ignore` after the note trail explains why.

### curl Example

With a project key (no project context needed):

```bash
curl -X POST http://localhost:3000/api/v1/exceptions \
  -H 'Authorization: Bearer YOUR_PROJECT_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "error": {
      "class_name": "TestError",
      "message": "Hello from curl!",
      "backtrace": ["app/test.rb:1:in test"],
      "first_line": {"file": "app/test.rb", "line": 1, "method": "test"}
    },
    "app": {"environment": "development"}
  }'
```

With a user key (cross-project) — add `X-Project-Id`:

```bash
curl -X POST http://localhost:3000/api/v1/exceptions \
  -H 'Authorization: Bearer YOUR_USER_KEY' \
  -H 'X-Project-Id: 42' \
  -H 'Content-Type: application/json' \
  -d '{...}'
```

## Configuration

All configuration is via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SECRET_KEY_BASE` | *(dev auto)* | Required in production |
| `OOPSIE_HOST` | `oopsie.example.com` | Public hostname, used for links in notification emails |
| `OOPSIE_FROM_EMAIL` | `notifications@example.com` | From address for outbound notification emails |
| `POSTMARK_API_TOKEN` | — | Postmark server API token for outbound email |
| `OOPSIE_ADMIN_EMAIL` | `admin@example.com` | Initial admin email (used on first `db:seed`) |
| `OOPSIE_ADMIN_PASSWORD` | *(random)* | Initial admin password (printed on first run) |
| `OOPSIE_RETENTION_DAYS` | `90` | Days to keep occurrence data before cleanup |
| `OOPSIE_SKIP_DEMO` | — | Set to `1` to skip demo data in `db:seed` |
| `OOPSIE_EXCEPTION_INGEST_CORS_ORIGINS` | `https://nerf-spring-break.netlify.app` | Comma-separated browser origins allowed to POST to `/api/v1/exceptions` |

See `.env.example` for a starter template.

## Fingerprinting

Exceptions are grouped by a SHA256 fingerprint of:

```
error.class_name + error.first_line.file + error.first_line.method
```

Method name is used instead of line number because line numbers shift with every edit, creating false new groups. When `first_line` is missing, falls back to:

```
error.class_name + normalized(error.message)
```

Message normalization strips numbers, UUIDs, hex strings, and quoted strings before hashing.

## Notifications

Notifications fire when:
- A **new** error group appears
- A **resolved** error group receives a new occurrence (regression)

Notifications do **not** fire on repeat occurrences of known unresolved errors (no alert fatigue).

Channels:
- **Email** — ActionMailer with error details, backtrace, and link to Oopsie UI
- **Webhook** — POST JSON payload to any URL (Slack incoming webhooks, etc.)

Configure notification rules per project in Settings.

Notification rules can also be managed through the API/CLI. Webhook URLs often
contain embedded secrets, so prefer `--url-stdin` or `--url-file` instead of
putting the URL directly in shell history:

```bash
oopsie notifications --project myapp

printf '%s' "$OOPSIE_WEBHOOK_URL" | \
  oopsie notification create \
    --project myapp \
    --kind webhook \
    --url-stdin \
    --events error.created,error.reopened
```

Canonical notification events are `new_error` and `regression`. The CLI accepts
the aliases `error.created`, `error.reopened`, and `error.regressed`.

## Retention

Occurrences older than 90 days (configurable via `OOPSIE_RETENTION_DAYS`) are automatically deleted daily at 3am by a Solid Queue recurring job.

The `occurrences_count` on each error group is a **lifetime total** — it reflects how many times the error has occurred, even after old occurrence rows are pruned.

## Deploy

### Hosted Oopsie production

The hosted production instance at `https://oopsie.sunflower-vacations.com` deploys from the `main` branch. For normal Symphony/Codex release work, merge the approved pull request into `main` and then verify production with `/up` plus the feature-specific smoke checks. Do **not** treat the checked-in Kamal files as the normal deploy path for this hosted instance, and do not block a release on interactive Kamal SSH access.

### Self-hosted Oopsie

Oopsie is a standard Rails app. Deploy it anywhere you'd deploy Rails:

### Fly.io

```bash
fly launch
fly secrets set SECRET_KEY_BASE=$(bin/rails secret)
fly secrets set OOPSIE_ADMIN_EMAIL=you@example.com
fly secrets set OOPSIE_ADMIN_PASSWORD=your-secure-password
fly deploy
```

### Any VPS (Ubuntu)

```bash
# Install Ruby 4.0.2, bundler, and SQLite
git clone https://github.com/theinventor/Oopsie.git
cd Oopsie
bundle install --without development test
RAILS_ENV=production bin/rails db:prepare
RAILS_ENV=production bin/rails db:seed
RAILS_ENV=production bin/rails server -b 0.0.0.0
```

Run Solid Queue in a separate process or use `bin/dev` which starts both.

### Health Check

`GET /up` returns 200 when the app is healthy. Use for load balancer health checks.

## Development

```bash
bin/setup --skip-server  # Install deps, prepare DB, seed data
bin/dev                  # Start server + Solid Queue
bin/rails test           # Run test suite (91 tests)
bin/rails console        # Rails console
```

## License

MIT
