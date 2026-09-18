---
name: oopsie
description: |
  Fetch and manage production exceptions from your Oopsie error tracker.
  Use when the user asks to "check errors", "what's broken", "show exceptions",
  "fix production errors", "check oopsie", or wants to investigate, resolve,
  ignore, or reopen error groups. Also use when the user says "oopsie" in the
  context of error tracking.
argument-hint: "[command] [args...]"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Edit
---

# Oopsie — Exception Tracker CLI

You have access to the `oopsie` CLI tool which connects to the user's self-hosted
Oopsie exception tracking server. Use it to fetch, inspect, and manage exceptions.

## CLI Version Guard

Before using workflow-state or note commands, verify the installed CLI is new
enough:

```bash
command -v oopsie
oopsie version
```

Workflow state and notes require `oopsie 0.4.0` or newer. Webhook setup/test
with `--json` (and `oopsie-mcp`) require `oopsie 0.6.0` or newer. If an authenticated
local CLI is older, update only the CLI script from the shipped source and do not
read, print, or rewrite `~/.oopsie/config.json`:

```bash
curl -fsSL https://raw.githubusercontent.com/theinventor/Oopsie/main/cli/oopsie -o /tmp/oopsie
chmod +x /tmp/oopsie
install -m 755 /tmp/oopsie ~/.local/bin/oopsie
hash -r
oopsie version
oopsie whoami
```

## Concepts

- A **connection** is a local config entry: a server URL + an API key (optionally pinned to a default project). Managed with `oopsie config`.
- A **project** is a remote app on the Oopsie server. Errors belong to projects.
- There are two API key types:
  - **User API key** — cross-project. Needs a project specified for scoped commands.
  - **Project API key** — one specific project. Project is implicit.

Config lives at `~/.oopsie/config.json`. Don't display full keys — they're sensitive.

Hosted clients (ChatGPT, Grok) cannot run this CLI. They must use the remote MCP at
`https://<oopsie-host>/mcp` with `Authorization: Bearer <user API key>` and pass
`project` on tool calls.

## Setup (only if not already configured)

Check connections:

```bash
oopsie config list
```

If none configured, ask the user for:
- A **connection name** (e.g. "prod", "staging")
- The **server URL** (e.g. `https://oopsie.example.com`)
- The **API key** — prefer the User API key from the Account page for multi-project access

```bash
oopsie config add <name> --server <url> --key <key> [--project <default_project>]
```

## Orientation Commands

Always start here when you're unsure what you're looking at:

```bash
oopsie whoami        # current connection, auth type, project count
oopsie projects      # list every project this key can access
```

`whoami` tells you if the key is a user key (cross-project) or project key (single).
`projects` shows names, IDs, unresolved counts, totals — use it to pick a target.

## Scoping Commands to a Project

Commands that operate on project resources (`project`, `errors`, `show`, `resolve`, `ignore`, `reopen`, `notifications`, `notification create`, `webhook setup`, `webhook test`, `webhooks`) need a project scope. In order of precedence:

1. `--project <name-or-id>` flag on the command
2. A project pinned on the connection via `oopsie config set-project <name>`
3. (Project keys only) — implicit

If you use a user key without either, the CLI returns:
`No project scoped. Use '--project <name>' or 'oopsie config set-project <name>'.`

## Commands Reference

### Config
```bash
oopsie config list
oopsie config add <name> --server <url> --key <key> [--project <name>]
oopsie config use <name>                        # set default connection
oopsie config set-project <name> | --clear      # pin/unpin project on current connection
oopsie config remove <name>
```

### Info
```bash
oopsie whoami
oopsie projects
oopsie project [--project <name>]               # summary of one project
```

### Errors
```bash
oopsie errors [--status unresolved|resolved|ignored] [--workflow-state untriaged|looking|in_progress|blocked|ready_to_resolve] [--limit N] [--offset N] [--project <name>]
oopsie show <error_group_id> [--project <name>]
oopsie state <error_group_id> <workflow_state> [--note <text>|--note-stdin|--note-file <path>] [--project <name>]
oopsie note <error_group_id> --body <text>|--body-stdin|--body-file <path> [--project <name>]
oopsie resolve <error_group_id> [--note <text>|--note-stdin|--note-file <path>] [--project <name>]
oopsie ignore <error_group_id> [--note <text>|--note-stdin|--note-file <path>] [--project <name>]
oopsie reopen <error_group_id> [--note <text>|--note-stdin|--note-file <path>] [--project <name>]
```

Workflow states are separate from lifecycle status:
`untriaged`, `looking`, `in_progress`, `blocked`, and `ready_to_resolve`.

### Notifications
```bash
oopsie notifications [--project <name>]                    # list configured destinations
oopsie notifications --kind webhook [--project <name>]      # list only webhooks
oopsie webhooks --json [--project <name>]                   # machine-readable webhook list

# Prefer stdin JSON for webhook URLs and headers so they are not stored in shell history.
printf '%s' '{"url":"'"$OOPSIE_WEBHOOK_URL"'","headers":{"Authorization":"Bearer '"$TOKEN"'"}}' | \
  oopsie webhook setup --input-json - --json --project <name>

oopsie webhook test <rule_id> --json --project <name>

# Older create path (still valid). Prefer setup when the caller needs idempotency.
printf '%s' "$OOPSIE_WEBHOOK_URL" | \
  oopsie notification create --project <name> --kind webhook --url-stdin --events error.created,error.reopened
```

Canonical events are `new_error` and `regression`. The CLI also accepts aliases
`error.created`, `error.reopened`, and `error.regressed`. Never print webhook URLs
or header values back to the user.

### Global flags
- `-p, --project <name|id>` — scope to a specific project (one-off override)
- `-c, --connection <name>` — use a non-default connection
- `--json` — machine-readable `{protocol_version, ok, result|error}` on webhook setup/test/list and `version`

## Workflow: Investigating and Fixing Errors

1. **Orient**: `oopsie whoami`, then `oopsie projects` if using a user key. If you don't know which project matches the current codebase, pick the closest name match or ask.
2. **Fetch unresolved**: `oopsie errors --status unresolved --project <name>`
3. **Inspect**: `oopsie show <id>` for stack traces, file/line/method, context, environment.
4. **Locate**: use `first_line` (file, line, method) from occurrences to jump to the bug in the current project's codebase.
5. **Claim workflow state**: before work, run `oopsie state <id> looking --note "starting investigation"` or `oopsie state <id> in_progress --note "implementing fix"`.
6. **Diagnose and fix**: read the relevant source files, understand the bug, implement a fix.
7. **Record evidence**: use `oopsie note <id> --body "..."` for repro steps, cause, PR, deploy, and verification details.
8. **After fixing**: ask whether to `oopsie resolve <id> --note "..."` or `oopsie ignore <id> --note "..."`.

## Handling $ARGUMENTS

When `/oopsie` is invoked, map arguments to commands:
- `/oopsie` — summary: `oopsie whoami` then `oopsie errors --status unresolved --limit 10` (scoping if pinned)
- `/oopsie errors` — `oopsie errors --status unresolved`
- `/oopsie show 42` — `oopsie show 42`
- `/oopsie state 42 in_progress` — `oopsie state 42 in_progress`
- `/oopsie note 42 found bad params` — `oopsie note 42 --body "found bad params"`
- `/oopsie fix` or `/oopsie what's broken` — fetch unresolved errors and start investigating
- `/oopsie resolve 42` — `oopsie resolve 42`
- `/oopsie setup` — walk through `oopsie config add`
- `/oopsie projects` — `oopsie projects`

## Tips

- Error group IDs are stable — reference them as `#<id>` in conversation.
- Occurrence `context` may contain request params, user IDs, or other debugging info.
- If `first_line.file` points into `.next/` or a build artifact, map it back to the source file before reading.
- Treat natural-language args as intent: "show me what's broken" → `oopsie errors --status unresolved`.

Arguments: $ARGUMENTS
