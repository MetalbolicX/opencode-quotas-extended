# OpenAI Raw-Key Platform Endpoint — Mock-Only Status

## Distinction: OAuth WHAM vs Raw-Key Platform

OpenAI exposes two separate quota surfaces:

| Variant | Auth | Endpoint | Pagination |
|---|---|---|---|
| **OAuth** (ChatGPT Plus/Pro) | OAuth2 Bearer token | `GET https://chatgpt.com/backend-api/wham/usage` | None — single response |
| **Raw API key** (platform.openai.com) | `Authorization: Bearer <OPENAI_API_KEY>` | `GET https://api.openai.com/v1/usage` | Cursor-based: `has_more` + `next_page` |

The `createOpenAIProvider` in `src/adapters/providers/openai.ts` implements both paths.
The OAuth WHAM path is gated by `cred.variant === "oauth"`.
The raw-key platform path is used for `variant === "api"` / `variant === "wellknown"` / env-var.

## Slice 9 Implementation (Mock-Only)

The raw-key `/v1/usage` pagination loop was implemented in slice 9 but remains **mock-only** because:

1. Live capture requires a real `OPENAI_API_KEY` with non-zero usage on platform.openai.com
2. The endpoint returns aggregated token counts per model, scoped to the API key's organization
3. No organizational scope (orgId equivalent) is needed for the platform usage endpoint

## How to Enable Live Capture

To switch from mock to live:

```bash
# Set your platform API key
export OPENAI_API_KEY="sk-proj-..."

# Run the quotas command targeting the openai provider
opencode-quotas --providers=openai
```

The `isAvailable()` check only confirms a credential is present (any variant).
Live validation requires actual non-zero usage on the account.

## Cursor Pagination Mechanics

The OpenAI platform `/v1/usage` cursor pagination:

```
Request 1: GET https://api.openai.com/v1/usage
Response: { data: [...], has_more: true, next_page: "cursor_abc" }

Request 2: GET https://api.openai.com/v1/usage?page=cursor_abc
Response: { data: [...], has_more: false, next_page: null }
```

- **Cap**: 20 pages maximum to prevent runaway loops on malformed responses
- **Failure isolation**: if page 1 succeeds but page N throws (500/network), page 1 entries are returned — no error surfaced
- **Deduplication**: first-write-wins by entry `id` field
- **Defensive parse**: absent, null, or non-boolean `has_more` treated as terminal; non-string `next_page` treated as terminal

## Relevant Files

| File | Role |
|---|---|
| `src/adapters/providers/openai.ts` | Dual-path provider (OAuth WHAM + raw-key paginated) |
| `tests/unit/providers/openai.test.ts` | 18 tests: WHAM unchanged + 8 pagination scenarios |
| `tests/fixtures/providers/openai/platform-usage.json` | Single-page mock (slice 1 fixture) |
| `tests/fixtures/providers/openai/platform-usage-multipage.json` | Multi-page mock structure (slice 9) |
| `notes/anthropic-admin-scope-blocked.md` | Same pattern: mock-only with live-capture instructions |
