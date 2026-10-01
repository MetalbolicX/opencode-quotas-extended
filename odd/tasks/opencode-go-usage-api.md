# Feature: opencode Go — official usage API

## Goal

Replace the dead pinned endpoint of the `go` provider with the official OpenCode Go
subscription usage API. No web scraping — API only.

## Research evidence (2026-02, verified)

- **Official endpoint exists and is live**: `GET https://opencode.ai/zen/go/v1/usage`
  - Auth: `Authorization: Bearer <API key>` — the regular `opencode-go` API key
    (written by `/connect` into `~/.local/share/opencode/auth.json`).
  - Added upstream in anomalyco/opencode PR #16513 (merged 2026-08-11, closes #16017).
  - Live probe (no key): `401 {"type":"error","error":{"type":"AuthError","message":"Missing API key."}}`
    — exactly matches the merged server source (`packages/console/app/src/routes/zen/go/v1/usage.ts`).
- **Response 200**:
  ```json
  {
    "usage": {
      "rolling": { "status": "ok" | "rate-limited", "percent": 19.5, "resetsAt": "2026-08-24T18:22:00.952Z" },
      "weekly":  { "status": "...", "percent": 0.0,  "resetsAt": "..." },
      "monthly": { "status": "...", "percent": 0.0,  "resetsAt": "..." }
    }
  }
  ```
  - `percent` is 0–100 (confirmed by tokscale PR #1189 `used_percent` mapping and
    @mellena1/opencode-go-usage).
- **403** `{"type":"error","error":{"type":"EntitlementError","message":"OpenCode Go subscription required."}}`
  without an active subscription.
- **Adopted by third parties (no scraping)**: tokscale PR #1189 (merged),
  `@mellena1/opencode-go-usage`, opencodex PR #1545, cc-switch issue #6433.
- **Side finding**: the endpoint currently pinned by both `zen` and `go` adapters in
  this repo (`https://opencode.ai/api/billing/balance`) returns **404** — dead.
  Zen keeps its deferred status; its replacement endpoint (if any) is out of scope here.

## Non-goals

- No web scraping of the dashboard.
- No changes to the Zen provider (separate follow-up decision needed: pinned endpoint is dead).
- No new env-var credential source for `opencode-go` (auth.json is the documented path).

## Tasks

1. [x] Research official API (done — evidence above).
2. [x] Add `GoParser` (`src/Providers/CodingPlanParse/GoParser.res`) + facade re-export,
      TDD: `src/Providers/GoParserTests.res` first (7 tests, RED→GREEN).
3. [ ] Rewire `src/Providers/Go.res` to `https://opencode.ai/zen/go/v1/usage` + GoParser.
4. [x] Docs: README (lines 35 + 139) + CLAUDE.md provider status table (Go → Production).
5. [x] Gates: 7/7 PASS — codegen --check, res:build (1 pre-existing base-only warning in
      ReportPipeline.res, from main 9ec400a), test (54 files), build, smoke --help,
      check-secrets, git diff --check. Verified by gentle-ai-verify.
6. [x] Work-unit commits on `feature/opencode-go-usage-api` (see evidence).

## Mapping (parser contract)

| API key   | window        | id            | info        |
|-----------|---------------|---------------|-------------|
| `rolling` | `#rolling5h`  | `go-rolling`  | `Go 5h`     |
| `weekly`  | `#rollingWeekly` | `go-weekly` | `Go Weekly` |
| `monthly` | `#monthly`    | `go-monthly`  | `Go Monthly`|

- `used` = `percent`, `limit` = `Some(100)`, `unit` = `"%"`.
- `reset` = `Some(Date.fromTime(jsDateParse(resetsAt)))` when present and not NaN, else `None`.
- Missing `percent` for a window → skip that entry; missing/invalid `usage` object → `[]`.

## Commit evidence

- `4951925` feat(go): parse official subscription usage API envelope
- `b9f786d` feat(go): fetch Go quota from official usage endpoint

## Follow-ups (out of scope here)

- Zen: pinned endpoint `api/billing/balance` is dead (404); needs a decision
  (scrape / find replacement endpoint / drop provider).
- Pre-existing warning 27 (unused `reason`) in `src/application/ReportPipeline.res:47`.
- Stale doc figure: CLAUDE.md test-file count (says 47, observed 54).
