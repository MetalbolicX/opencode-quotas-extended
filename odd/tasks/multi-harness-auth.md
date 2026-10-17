# Feature: multi-harness auth (opencode + pi) and Claude Code subscription usage

> ODD feature document. Created before the first source write. Branch: `feat/multi-harness-auth`.
> Engram mirror: `odd/multi-harness-auth/tasks`. Read until `## Log`.

## Specs

- **S1 — pi credentials.** "use pi authentication to get the automatic API key to use subscriptions".
  Read `~/.pi/agent/auth.json` as a second harness source. pi stores API keys as
  `"type": "api_key"` (opencode: `"api"`); both decode to an API credential. pi uses its
  own key names (`openai-codex`, `zai`, `minimax`, `opencode-go`), so each harness has its
  own provider-key map.
- **S2 — Overlap and union.** "We need to consider what if opencode has all subscriptions and
  pi too, if any harness has one more than the other". Decision: "Ordered + fallthrough".
  Default order opencode → pi (then env → config), changeable via an optional
  `credentialSources` setting in `quotas.json`. A provider present in only one harness is
  still resolved. A provider tries candidates in order and moves to the next when a token is
  expired and cannot be refreshed, or on HTTP 401; it records an error only when every
  candidate fails.
- **S3 — pi OAuth is read-only.** Decision "pi OAuth read-only: Yes". Never write pi's
  `auth.json`. An expired pi OAuth token falls through to the next candidate; if it is the
  last, the error tells the user to run pi to refresh. OpenAI refresh write-back persists
  only to the file the credential came from (opencode), never across harnesses.
- **S4 — Claude Code subscription.** "I am have an antrophic subscription now, but the token
  should be on claude login like openai, it require me use login via browser". Decisions:
  "Read-only, ask to re-run claude"; Anthropic subscription source: "Claude Code login".
  Read `~/.claude/.credentials.json` (`claudeAiOauth`, honor `CLAUDE_CONFIG_DIR`), never
  write it. Expired `expiresAt` → rejected with
  "Claude Code token expired — run `claude` to refresh". Usage rows (5h, weekly, weekly
  Opus/Sonnet) as % with reset times from the subscription usage endpoint.
- **S5 — Admin API kept as fallback.** "Keep it as fallback." The existing
  `ANTHROPIC_API_KEY` + `ANTHROPIC_ORG_ID` admin org-usage path stays, tried after the
  Claude Code candidate.
- **S6 — Gemini out of scope.** "Yes, I don't have a subscription to check that is getting
  the correct info". Gemini credential resolution is unchanged.

## Tasks

| ID | Specs | Task | Route | Commit |
|---|---|---|---|---|
| T0 | S1, S4 | Read-only checks: pi auth path override, pi provider IDs (kimi/anthropic), pi auth.json locking; live probe of Claude usage endpoint → redacted fixture | inline | — (done, L5–L6) |
| T1 | S1 | `Credential.fromJson` accepts `api_key` | inline | fd21edf |
| T2 | S1, S2 | Harness auth source (path + key map), pi path, `credentialSources` schema, `resolveAll` with origin | inline | T2+T3 commit (L7) |
| T3 | S2, S3 | Fallthrough in OpenAI/Go/z.ai/Kimi (Minimax: first candidate, L8); origin-scoped refresh; pi OAuth read-only | inline | T2+T3 commit (L7) |
| T4 | S4, S5 | `ClaudeCodeSource` + Anthropic subscription rows; admin path as fallback; labels | gentle-ai-worker (context backstop) | T4 commit (L11) |
| T5 | S1–S6 | README, CLAUDE.md, help text (no flag changes; help already names anthropic) | inline | T5 commit |

## Log

- **L1** (user, original request): "Lets plan to expand this project so that I can also use pi
  authentication to get the automatic API key to use subscriptions. We need to consider what if
  opencode has all subscriptions and pi too, if any harness has one more than the other. In
  addition, I am have an antrophic subscription now, but the token should be on claude login
  like openai, it require me use login via browser. We're planning"
- **L2** (user, questionnaire): outside reads "Yes, structure only"; overlap "Ordered +
  fallthrough"; Claude refresh "Read-only, ask to re-run claude"; Anthropic sources
  "Claude Code login".
- **L3** (evidence, structure-only reads): pi auth.json keys `minimax`, `zai`, `opencode-go`
  (`type: api_key`), `openai-codex` (`type: oauth`, access/refresh/expires/accountId).
  opencode auth.json keys `openai` (oauth), `opencode`, `opencode-go`, `minimax-coding-plan`,
  `zai-coding-plan`, `kimi-for-coding` (`type: api`). Claude `claudeAiOauth`:
  accessToken, refreshToken, expiresAt (number), refreshTokenExpiresAt, scopes,
  subscriptionType, rateLimitTier.
- **L4** (user): "1. Keep it as fallback. 2. Yes. 3. Yes, I don't have a subscription to check
  that is getting the correct info"
- **L5** (evidence, pi dist `config.js`): `getAgentDir()` = `$PI_CODING_AGENT_DIR` (tilde
  expanded) else `~/.pi/agent`; auth path `join(getAgentDir(), "auth.json")`. pi Kimi provider id
  is `kimi-coding` (baseUrl `https://api.kimi.com/coding/v1`). pi uses `proper-lockfile`
  (supports S3 read-only).
- **L6** (evidence, live probe, user-consented): `GET https://api.anthropic.com/api/oauth/usage`
  with `Authorization: Bearer <claude accessToken>` + `anthropic-beta: oauth-2025-04-20` → HTTP 200.
  Shape: `five_hour`/`seven_day` `{utilization, resets_at(ISO)}`; `seven_day_opus`/`_sonnet` null;
  `limits[]` `{kind: session|weekly_all|weekly_scoped, group, percent, resets_at,
  scope: null | {model: {display_name}}}`. Values: session 7%, weekly_all 4%, weekly_scoped
  "Fable" 0%.
- **L7** (decision): T2 and T3 ship in one commit. Exposing pi's OAuth entry before origin-scoped
  refresh existed would let the opencode refresh path rotate pi's token (violates S3).
  Fallthrough triggers: messages containing "HTTP 401", "HTTP 403" (wrong key type, e.g. a
  non-coding-plan key) or `expiredHint` ("expired — run"); other errors reject immediately.
- **L8** (decision): Minimax keeps first-candidate resolution. Its key path runs
  `mmx auth login --api-key`, which mutates the mmx CLI session; cycling candidates there would
  be a side effect, not a read.
- **L9** (slice boundary): slice 1 = T1–T3 (`fd21edf`, `415662a`, ~780 lines). T4–T5 form slice 2.
- **L10** (T4 design, parent decision):
  - `Paths.getClaudeCredentialsPath(~env)`: `$CLAUDE_CONFIG_DIR/.credentials.json`, else
    `~/.claude/.credentials.json`; re-exported from `Infra`.
  - New `src/Auth/ClaudeCodeSource.res(+.resi)`: read-only `getCredential(~env)` that decodes
    `claudeAiOauth.{accessToken, refreshToken, expiresAt}` → `Credential.OAuth`. No write function.
  - `CredentialResolver.resolveAllWith`: for provider id `"anthropic"` only, a `#claudeCode`
    candidate comes FIRST, before harness/env/config candidates (S4 primary, S5 fallback).
  - `Anthropic` provider uses `resolveEach`: `#claudeCode` OAuth → subscription path; every other
    candidate → the existing admin org-usage path, unchanged (S5).
  - Subscription path: expired (`expires > 0 && now >= expires`) → reject with exactly
    "Claude Code token expired — run `claude` to refresh" (contains `expiredHint`), no HTTP.
    Otherwise `GET https://api.anthropic.com/api/oauth/usage` with
    `Authorization: Bearer <access>` and `anthropic-beta: oauth-2025-04-20`.
  - Pure parser over the L6 shape: rows from `limits[]` (`session` → 5h, `weekly_all` → weekly,
    `weekly_scoped` → weekly <model display_name>, unknown kinds kept generically), `percent`
    clamped 0–100, `limit` 100, unit `%`, reset from `resets_at`. When `limits` is absent or
    empty, fall back to `five_hour` / `seven_day` / `seven_day_opus` / `seven_day_sonnet`
    `utilization`.
- **L11** (evidence, T4): worker RED→GREEN, 59 test files pass; parent re-ran build/test/secrets/codegen
  (all exit 0). Live CLI run `-p anthropic`: "5h rolling window 9%", "Weekly limit 4%",
  "Weekly limit (Fable) 0%" from the Claude Code login. Anthropic metadata → category
  `subscription`, authStrategy `#oauth` (no consumer branches on them).
- **L12** (evidence, differential vs `main` in a scratch worktree, numbers normalized): `-p` zai/go/kimi/
  minimax/openai/gemini/zen/bogus identical exit code, stdout and stderr. Only `--list` differs:
  Anthropic now "available" (requested, S4). Slice 2 = T4–T5.
- **L13** (review): assess on slice 2 (base `415662a`) → `reviewDue: true` (high_risk, auth). Inspect
  stopped with `managed_assets_outdated`; continuation is
  `~/.pi/agent/npm/node_modules/gentle-pi/.gentle-ai/v4.2.0/gentle-ai sync --agent pi` (writes outside
  the repo) → awaiting user decision. Inspect also projected the whole branch vs `origin/main`
  (31 paths), not the slice.
