# Session Handoff — Missing Implementations (`pin-provider-endpoints` resume)

## Next Session Focus

Resume the archived `pin-provider-endpoints` cycle by implementing the **5 deferred slices** that require credentials not present in `~/.local/share/opencode/auth.json`. Resume order (dependency-driven):

1. **Slice 7** — anthropic-orgid (needs `ANTHROPIC_API_KEY` admin + `orgId`)
2. **Slice 8** — gemini-headers (needs `GEMINI_API_KEY`)
3. **Slice 9** — openai-pagination (needs raw `OPENAI_API_KEY`, NOT OAuth)
4. **Slice 12** — info-window-fields (unblocks after 7 + 8 + 9)
5. **Slice 13** — integration-readme (last; asserts all 8 providers contribute rows)

Then run final `sdd-verify` (≥393 tests, all gates green) and `sdd-archive` to close the cycle.

---

## Context & Summary

The `pin-provider-endpoints` follow-up cycle was archived as **PARTIAL** on 2026-07-26 (obs #3691, #3692). The hexagonal architecture is locked; 8 of 13 slices landed on `main` via local merge (no git remote configured in this repo). 393 tests pass; all 5 preflight gates are green.

**What landed (8 slices, 113 new tests, +278 production lines + 137 test-only lines):**
- `CacheSource` port + `QuotaCache` adapter with single-flight in-flight coalescing and bounded history (10k-refresh leak-guard)
- 5 default coding-plan aggregation groups (most_critical) + user-wins merge
- Cache wired into the report-pipeline + showUnaggregated + provider/model filters + Anthropic `orgId` resolver (config → auth.json → env)
- `show: boolean` tri-state (simple|detailed|hidden) preserving `displayMode` (table|json|markdown)
- OAuth single-flight refresh under 50-caller storm
- 10k-refresh identity-safe invalidation
- `https://api.openai.com/v1/usage` URL pinned (OAuth 401 handled gracefully)
- 5 coding-plan endpoints pinned (zen/go/zai/kimi via parseUsage + windowMap; minimax via mmx CLI + parseMinimaxCli)

**What's missing (5 slices):** anthropic + gemini are not in `auth.json`; the stored `openai` entry is OAuth, which 401s on `/v1/usage`. Slices 12 + 13 unblock after 7, 8, 9.

**3 pre-existing bugs fixed incidentally during slice 3:**
- `aggregateMostCritical` never picked best when all ETTL were `Infinity` → fixed `if (!best || t < minTime)`
- `undefined` `ettlMap` threw → added `ettlMap ?? {}` null-coalescing
- `aggregateMedian([])` threw on empty array → added `if (length === 0) return null` guard

---

## What's Pending — Per-Slice Implementation Guide

### Slice 7 — anthropic-orgid

**Spec** (from `sdd/pin-provider-endpoints/spec` Capability 3): Use `https://api.anthropic.com/v1/organizations/{org_id}/usage` (NOT `/v1/usage` — that endpoint does not exist). Auth headers: `x-api-key: <key>` + `anthropic-version: 2023-06-01`. Paginated (`has_more` / `next_page`). Standard API keys 403 — admin scope required.

**Files to modify:**
- `src/adapters/providers/anthropic.ts` — replace `TODO(research)`, implement `fetchQuotas`
- `src/adapters/infra/config-loader.ts` — `resolveAnthropicOrgId` is already implemented (slice 4)
- `schemas/quotas.schema.json` — `anthropic.orgId` field is already added (slice 4)
- `tests/unit/providers/anthropic.test.ts` — extend
- `tests/fixtures/providers/anthropic/usage.json` — new, redacted live capture

**Acceptance scenarios** (already specified):
- `orgId resolved from config` — config has `anthropic.orgId`, mocked 200 → returns `QuotaData[]`
- `orgId resolved from auth.json` — fallback works
- `orgId resolved from env` — `ANTHROPIC_ORG_ID` env fallback works
- `missing orgId fails fast` — clear actionable error, no silent `[]`
- `insufficient scope fails fast` — 403/401 surfaces a clear error message

**Δ budget**: ≤350 lines.

**Capture protocol:**
1. Add `ANTHROPIC_API_KEY` (admin key with `usage:read` scope) and `anthropic.orgId` to `~/.local/share/opencode/auth.json`. Schema: `{ "anthropic": { "key": "...", "orgId": "..." } }`.
2. `KEY=$(jq -r '.anthropic.key' ~/.local/share/opencode/auth.json)` and `ORG=$(jq -r '.anthropic.orgId' ~/.local/share/opencode/auth.json)` (in shell, never logged).
3. `curl -sS -H "x-api-key: $KEY" -H "anthropic-version: 2023-06-01" "https://api.anthropic.com/v1/organizations/$ORG/usage?limit=31" -o /tmp/anthropic.json`
4. If 200: redact `walk(if type == "object" then with_entries(if .key | test("key|access|refresh|token") then .value = "****" else . end) else . end) /tmp/anthropic.json` and save to `tests/fixtures/providers/anthropic/usage.json`.
5. If 403/401: surface the error in `notes/anthropic-admin-scope-blocked.md` and stop with a `partial` status. The README must document the admin-key requirement.

---

### Slice 8 — gemini-headers

**Spec** (from `sdd/pin-provider-endpoints/spec` Capability 3): For Google AI Studio, no aggregate endpoint exists. Derive usage from per-request rate-limit response headers via `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent` (1-token probe). Auth: `x-goog-api-key: <key>` (or `?key=...`). Headers to read: `x-ratelimit-remaining-requests`, `x-ratelimit-remaining-tokens`, `x-ratelimit-reset`. Map to `QuotaData[]` representing rpm/rpd windows. Graceful `[]` + warning if headers absent.

**Files to modify:**
- `src/adapters/providers/gemini.ts` — replace `TODO(research)`, implement `fetchQuotas` reading headers
- `tests/unit/providers/gemini.test.ts` — extend (header parse + absent-header fallback)
- `tests/fixtures/providers/gemini/headers.txt` — new, redacted live capture (HTTP response headers)

**Acceptance scenarios:**
- `headers mapped to windows` — mocked response with `x-ratelimit-remaining-requests=42` etc. → `QuotaData[]` with rpm/remaining windows
- `headers absent → graceful` — no headers → `[]` + redacted warning, no throw
- `1-token probe` — body `{"contents":[{"parts":[{"text":"hi"}]}],"generationConfig":{"maxOutputTokens":1}}`

**Δ budget**: ≤300 lines.

**Capture protocol:**
1. Add `GEMINI_API_KEY` to `~/.local/share/opencode/auth.json`. Schema: `{ "gemini": { "key": "..." } }`.
2. `KEY=$(jq -r '.gemini.key' ~/.local/share/opencode/auth.json)`.
3. `curl -sS -H "x-goog-api-key: $KEY" -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent" -d '{"contents":[{"parts":[{"text":"hi"}]}],"generationConfig":{"maxOutputTokens":1}}' -D - -o /dev/null > /tmp/gemini-headers.txt` (capture headers).
4. Redact any sensitive fields in the captured headers (e.g., `key`) and save to `tests/fixtures/providers/gemini/headers.txt`.

---

### Slice 9 — openai-pagination

**Spec** (from `sdd/pin-provider-endpoints/spec` Capability 3): The openai `/v1/usage` endpoint is paginated (`has_more` / `next_page`). The adapter must follow pagination up to a sane cap and aggregate across pages; must not loop unbounded. The current implementation in `src/adapters/providers/openai.ts` does NOT paginate (it reads `total_usage` once). The pagination seam was reserved during slice 1.

**Files to modify:**
- `src/adapters/providers/openai.ts` — add pagination loop with `has_more` cap
- `tests/unit/providers/openai.test.ts` — extend with multi-page scenarios

**Acceptance scenarios:**
- `multi-page aggregated` — mocked 2 pages, has_more=true on first, has_more=false on second → entries from both, loop terminates
- `unbounded pagination cap` — mocked infinite has_more=true (e.g., 100 pages) → loop terminates at cap (e.g., 20)
- `pagination failure isolation` — first page 200, second 500 → first page entries returned, no throw

**Δ budget**: ≤250 lines.

**Capture protocol:**
- The current `openai` entry in `auth.json` is OAuth (Google OAuth via opencode.ai auth), NOT a raw API key. OAuth tokens return 401 from `/v1/usage`.
- For slice 9 to do live capture, the user must add a raw `OPENAI_API_KEY` to `auth.json` under a new entry like `{ "openai": { "key": "sk-..." } }`. The adapter must distinguish between OAuth and API-key variants (already done in slice 1).
- If the user cannot provide a raw key, do architectural implementation only with mocked tests, and document the live-capture constraint in `notes/openai-raw-key-blocked.md`.

---

### Slice 12 — info-window-fields

**Spec** (from `sdd/pin-provider-endpoints/spec` + `tasks`): Verify and add per-provider `info` and `window` field tests. The 5 coding-plan providers (zen/go/zai/kimi/minimax) already have these populated from slice 6. The work for slice 12 is to add the same coverage for **openai** (OAuth), **anthropic** (after slice 7), and **gemini** (after slice 8).

**Files to modify:**
- `src/adapters/providers/openai.ts` — verify `info` is populated for `openai-primary` / `openai-secondary` / `openai-credits` (already done in slice 1)
- `src/adapters/providers/anthropic.ts` — populate `info` and `window` per entry
- `src/adapters/providers/gemini.ts` — populate `info` and `window` per entry
- `tests/unit/providers/{openai,anthropic,gemini}.test.ts` — add info/window assertions

**Acceptance scenarios:**
- `openai info populated` — primary window has `info: "primary"`, secondary has `info: "secondary"`, credits has `info: "unlimited"` or `info: "balance"`
- `anthropic info populated` — each entry has a meaningful `info` string
- `gemini info populated` — each rate-limit-derived entry has a meaningful `info` string
- `all providers use windowMap or strict union` — `window` field is never a free-form string at the domain boundary

**Δ budget**: ≤350 lines.

---

### Slice 13 — integration-readme

**Spec** (from `sdd/pin-provider-endpoints/spec` + `tasks`): Update integration test to assert all 8 providers contribute rows when fully wired. Update `README.md` open-issues section to remove the closed gaps. Document the Anthropic admin-scope requirement and the OAuth-vs-API-key distinction for openai.

**Files to modify:**
- `tests/integration/slice10.test.ts` (or `tests/integration/pipeline.test.ts`) — extend with 8-provider rows assertion
- `commands/quotas.md` — already fixed (slice 13 readme work is a no-op if already clean)
- `README.md` — open-issues section: remove closed gaps, document `anthropic.orgId` resolution priority, document admin-scope requirement, document OAuth vs raw API key for openai

**Acceptance scenarios:**
- `integration 8-provider rows` — mocked 8 providers each return 1+ QuotaData → pipeline renders 8 rows
- `registry has 8 providers` — `tests/unit/providers/registry.test.ts` asserts `registry.size === 8`
- `README open-issues updated` — manually verify in the diff

**Δ budget**: ≤300 lines.

---

## External Artifacts (link, don't duplicate)

### SDD cycle artifacts (engram topic keys)
- Plan: `sdd/pin-provider-endpoints/plan` (obs #3678)
- Proposal: `sdd/pin-provider-endpoints/proposal` (obs #3680)
- Spec: `sdd/pin-provider-endpoints/spec` (obs #3682) — full requirements + scenarios
- Design: `sdd/pin-provider-endpoints/design` (obs #3683) — architecture + interfaces
- Tasks: `sdd/pin-provider-endpoints/tasks` (obs #3685) — 13-slice breakdown with RED→GREEN→REFACTOR
- Apply progress: `sdd/pin-provider-endpoints/apply-progress` (obs #3687) — slices 2, 3, 4, 5, 10, 11, 1, 6
- Verify report: `sdd/pin-provider-endpoints/verify-report` (obs #3689) — partial verify
- Archive report: `sdd/pin-provider-endpoints/archive-report` (obs #3691) — PARTIAL CLOSED
- Cycle complete: `sdd/pin-provider-endpoints/cycle-complete` (obs #3692)
- State: `sdd/pin-provider-endpoints/state` (obs #3681) — phase=archive (closed partial)
- Auth keys: `auth/keys-pinned` (obs from this cycle)

### Project files
- `src/ports/cache.ts` (slice 2)
- `src/adapters/infra/quota-cache.ts` (slices 2, 11)
- `src/domain/aggregation-defaults.ts` (slice 3)
- `src/domain/aggregation.ts` (slice 3, +3 bug fixes)
- `src/domain/types.ts` — `window` strict union, `show: boolean` (slices 4, 5, 6)
- `src/application/report-pipeline.ts` (slice 4) — cache + defaults + filters
- `src/adapters/infra/config-loader.ts` (slice 4) — `resolveAnthropicOrgId`
- `schemas/quotas.schema.json` (slices 4, 5) — `anthropic.orgId`, `show: boolean`
- `src/plugin/footer-hook.ts` (slice 5) — show tri-state
- `src/plugin/index.ts` (slice 5) — config wiring
- `src/adapters/providers/oauth.ts` (slice 10) — single-flight refresh
- `src/adapters/providers/openai.ts` (slice 1) — URL pinned, 401 handler
- `src/adapters/providers/{zen,go,zai,kimi}.ts` (slice 6) — URLs pinned, parseUsage
- `src/adapters/providers/minimax.ts` (slice 6) — CLI-based, parseMinimaxCli
- `src/adapters/providers/coding-plan-parse.ts` (slice 6) — windowMap + parseUsage
- `src/adapters/providers/anthropic.ts` — **DEFERRED** (TODO(research) remains)
- `src/adapters/providers/gemini.ts` — **DEFERRED** (TODO(research) remains)
- `tests/fixtures/providers/{zen,go,zai,kimi,minimax}/usage.json` (slice 6)
- `tests/fixtures/providers/openai/platform-usage.json` (existed)

### Reference artifacts
- `plans/endpoint-exploration-handoff.md` — the prior handoff that started this cycle
- `sdd/quotas-rewrite/design` (obs #3670) — locked architecture (read first)
- `sdd/quotas-rewrite/apply-progress` (obs #3670) — slice delivery style reference
- `sdd/quotas-rewrite/archive-report` (obs #3676) — archive structure reference
- Reference clone: `/tmp/opencode-quotas-ref/src/{quota-cache,defaults}.ts`
- Auth keys: `jq 'keys' ~/.local/share/opencode/auth.json` (currently: kimi-for-coding, minimax-coding-plan, openai, opencode, opencode-go, zai-coding-plan)

---

## Pre-flight gates (must stay green across all 5 slices)

| Gate | Command | Required exit |
|---|---|---|
| Tests | `bun run test` | 0 — must reach ≥393 baseline + new tests |
| Typecheck | `bun run typecheck` | 0 |
| Build | `bun run build` | 0 |
| Secrets | `bash scripts/check-secrets.sh` | 0 — re-run before every commit |
| Git | `git status` | clean before each merge to main |

**Local merge pattern (no remote configured):**
```bash
git checkout -b slice/N-name
# ... RED → GREEN → REFACTOR ...
git add <files>
git commit -m "feat(<scope>): <description> (slice N)"
git checkout main
git merge --no-ff slice/N-name -m "merge(slice/N): <description>"
git branch -d slice/N-name
```

**Hard constraints:**
- NO hardcoded secrets. Always read from `auth.json` for live capture.
- NO live HTTP in unit tests. Always mock.
- NO changes to hexagonal layer boundaries.
- Slice Δ ≤ stated budget per slice.
- Strict TDD: RED → GREEN → REFACTOR per behavior.

---

## Suggested Skills for the Next Agent

- **`sdd-init`** — only if `sdd-init/opencode-quotas-extended` is missing from engram (it exists at obs #3661, so reuse — do NOT re-run)
- **`sdd-apply`** — primary; implement each of the 5 slices
- **`sdd-verify`** — final verification once all 5 slices land
- **`sdd-archive`** — close the cycle
- **`work-unit-commits`** — commit boundaries per slice
- **`chained-pr`** — `stacked-to-main` strategy (force-chained, 400-line budget)
- **`good-comments`** — comment style: *why* / *how*, never *what*
- **`diagnose`** — for endpoint shape mismatches during live capture
- **`web-coder`** — for HTTP/REST endpoint research (status codes, headers, pagination)
- **`context7_resolve-library-id`** + **`context7_query-docs`** — for current Anthropic, Gemini, OpenAI docs at capture time
- **`customize-opencode`** — for opencode plugin conventions

Do NOT load: `commit-process`, `review`, `skill-creator`, `skill-improver`.

---

## Acceptance Criteria for the Resume Cycle

The next cycle is done when:
1. **Zero `TODO(research)` in `src/`** — `grep -RE "TODO\(research\)" src/` exits 1
2. **8 fixtures committed** under `tests/fixtures/providers/<id>/`, all check-secrets clean
3. **No `return []` TODO guards** remain in any provider adapter
4. **All 8 providers contribute rows** in `tests/integration/pipeline.test.ts` (mocked)
5. **Test count ≥ 393 baseline** + new tests per slice
6. **All 5 preflight gates green** at end of each slice
7. **`README.md` open-issues section** documents the closed gaps + remaining caveats (Anthropic admin scope, OAuth vs raw API key for openai)
8. **Final `sdd-verify` PASS** (or PASS WITH WARNINGS only for environment-level issues, not implementation)
9. **Final `sdd-archive` CLOSED** — replaces the PARTIAL archive at obs #3691

### Risks for the resume cycle
- **Anthropic admin scope** may be unavailable on some account tiers → fail-fast with clear error + README docs
- **Gemini rate-limit headers** may not always be present → graceful `[]` + warning
- **OpenAI raw key** may not be available (OAuth-only) → mock-only implementation
- **Endpoint rotation** — zen/go/zai/kimi endpoints already showed 404 in the previous cycle; if the next capture also fails, document the auth/scope mismatch in `notes/<provider>-blocked.md`
- **`mmx` CLI execSync** — security/performance review needed if minimax adapter is to remain in production

---

## Critical reminders

1. **Read auth.json for live capture; never log keys; never commit keys.** The `scripts/check-secrets.sh` gate catches leaks, but defense-in-depth is mandatory.
2. **Redact fixtures recursively** before commit: `walk(if type == "object" then with_entries(if .key | test("key|access|refresh|token") then .value = "****" else . end) else . end)`.
3. **No git remote** — local merges to main only, per the previous cycle's pattern.
4. **Architecture is locked** — no changes to the hexagonal layer boundaries. New providers = adapter + registration only (OCP).
5. **Strict TDD** — every slice is RED → GREEN → REFACTOR per behavior. RED must fail before production code.
6. **Pre-flight cached** — `auto` / `engram` / `force-chained` / `400-line budget` / `strict TDD` / `bun run test`. Reuse from obs #3660 and #3661.
7. **Init guard** — `sdd-init/opencode-quotas-extended` (obs #3661) exists; do NOT re-run.
8. **Backwards compatibility** — all 393 existing tests MUST stay green; net test count only grows.
