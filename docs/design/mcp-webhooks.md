# Oopsie MCP — webhook setup and testing

Synthesized from the architect arena (2026-09-17).

## Problem

Agents need to create and verify Oopsie webhook notification rules without a browser. The existing human CLI can create webhooks, but destinations often contain secrets, there is no machine-readable envelope, and test-send lived only on the web form (including unsaved destinations). Wrapping today's human CLI cannot test a persisted rule, and a second HTTP client in the MCP would duplicate auth, project scoping, and `~/.oopsie/config.json`. The server already owns validation and destination masking; those must stay there.

## Usage (caller's view)

Configure the CLI once, then run the MCP server:

```json
{
  "mcpServers": {
    "oopsie": {
      "command": "oopsie-mcp",
      "env": { "OOPSIE_BIN": "/usr/local/bin/oopsie" }
    }
  }
}
```

```text
call oopsie_webhook_setup({
  project: "checkout",
  url: secret_url,
  headers: { "Authorization": receiver_token },
  events: ["new_error", "regression"],
  enabled: true
})
=> { created: true, notification_rule: { id: 42, destination_masked: "https://hooks.example.net/...", ... } }

call oopsie_webhook_test({ project: "checkout", rule_id: 42 })
=> { delivery: { rule_id: 42, delivered: true, http_status: 204, payload_kind: "connectivity_probe", failure: null } }

call oopsie_webhook_list({ project: "checkout" })
=> { webhooks: [ { id: 42, destination_masked: "...", headers_configured: true, ... } ] }
```

Equivalent CLI:

```bash
printf '%s' '{"url":"...","headers":{"Authorization":"Bearer ..."},"events":["new_error","regression"],"enabled":true}' |
  oopsie webhook setup --input-json - --json -p checkout

oopsie webhook test 42 --json -p checkout
oopsie webhooks --json -p checkout
```

## Shape

```
ChatGPT / Grok / xAI API
  -> POST https://oopsie-host/mcp   (Streamable HTTP, Bearer user or project API key)
       -> Mcp::Protocol / Mcp::WebhookTools
            -> WebhookRuleSetup / WebhookTestProbe / WebhookDelivery

local Cursor / Claude Code / grok CLI stdio
  -> oopsie-mcp (stdio JSON-RPC)
       -> oopsie --json  (bash CLI, ~/.oopsie/config.json)
            -> /api/v1/notification_rules/setup_webhook
            -> /api/v1/notification_rules/:id/test
            -> /api/v1/notification_rules
```

Hosted products cannot spawn stdio. The remote server is the Oopsie Rails app, not a wrapper around the CLI (there is no `~/.oopsie/config.json` in production). Local stdio stays an adapter for agents that already have the CLI configured.

Public MCP surface is three tools. Secrets enter in the tool arguments over HTTPS; they never appear in results (`destination_masked`, `headers_configured`).

Rails owns exact-match idempotency (destination + headers + events + enabled), outbound POST, and masking. `WebhookDelivery` is the shared poster and preserves `uri.request_uri` so query strings are not dropped. Test of a stored rule is a connectivity probe `{ event: "test", project, message }`, not a fake `new_error`. A failed receiver is a typed `delivery` result (`isError: false`). Auth failures are HTTP 401 with `WWW-Authenticate: Bearer`.

ChatGPT Developer mode accepts token auth for this endpoint. Full OAuth 2.1 (protected resource metadata, PKCE, ChatGPT redirect) is not in this slice.

## Synthesis decision

**Base: candidate-2** (stdio MCP over a versioned JSON CLI; Rails exact-match setup; test persisted rules by id; shared connectivity-probe transport).

The arena cross-judge scored that package 24/25. The parent agreed on the mental model: two complete operations (`setup`, `test`) rather than coordinating create-then-test, real exact-match idempotency, secrets on one stdin JSON document, and a typed delivery result that is not an MCP protocol error.

**Dropout:** Claude Fable 5 could not run (data-retention gate). Candidate-1 is the composer replacement.

### Grafts

- From candidate-1: `payload_kind: "connectivity_probe"` on the test result.
- From candidate-3: `oopsie_webhook_list` as a third tool (retest without a secret); disabled rules may still be probed; Ruby stdio MCP next to `cli/oopsie` instead of a TypeScript npm package.
- From candidate-4: redacting `Secret` wrapper; CLI version/schema gate; preserve URI query strings in the shared poster (the existing `uri.path`-only bug).

### Rejected

- Candidate-1 `--header` on argv.
- Candidate-3 mapping receiver 4xx to MCP `isError`.
- Candidate-4 destination fingerprint, production-shaped probe, rollback-on-failed-create, `verify: false`, mutating upsert, repo-wide CLI renderer rewrite.
- Blocking private/loopback webhook targets by default (self-hosted Oopsie often notifies internal services).

## Tradeoffs accepted

- We accept Bearer API keys (not OAuth 2.1) on `/mcp` in exchange for unblocking ChatGPT token auth and Grok `Authorization` headers without standing up an authorization server.
- We accept exact-match create (not upsert/patch) in exchange for never mutating an existing destination that an operator may still need.
- We accept a connectivity probe instead of a production-shaped `new_error` payload in exchange for never looking like a real incident to the receiver.
- We accept no default private-IP SSRF block in exchange for self-hosted Oopsie notifying internal services.
- Production delivery still retries timeouts: `WebhookDelivery` always returns a `Result`, and `WebhookDeliveryJob` re-raises `WebhookDelivery::TimeoutError` when `result.retryable?`. Retry policy stays at the job boundary.

## Alternatives considered

- **MCP as an HTTP client.** Smaller process graph, but it would own auth, project scoping, and config — complexity the CLI already hides. Lost because it splits the secret/config boundary.
- **Screen-scrape the human CLI.** No new flags, but callers would parse prose and could not test persisted rules. Lost on interface depth: the agent would have to know CLI layout.
- **Upsert plus rollback.** One "make this webhook work" call, but it mutates or deletes live rules when a probe fails. Lost because a failed receiver is not a reason to destroy configuration.

## Open questions and risks

- Should `--json` eventually cover every CLI command, or stay limited to machine callers (stdio MCP) until those commands exist as tools?
- When should email (or other channels) get MCP tools, given this slice is webhooks only?
- When should `/mcp` grow OAuth 2.1 (CIMD/DCR, `/.well-known/oauth-protected-resource`) so ChatGPT can use the connector OAuth flow instead of a pasted API key?

## Next implementation step

Fill in `WebhookDelivery` / `WebhookRuleSetup` / `WebhookTestProbe`, then `oopsie --json` webhook setup/test/list, then `cli/oopsie-mcp`.
