# Session Handoff — Endpoint Exploration & Reference-Plugin Gap Closure

## Next Session Focus

Two parallel workstreams for the next cycle (recommended SDD change: **`pin-provider-endpoints`**):

1. **Pin the 8 TODO(research) endpoint URLs** so the providers return real usage data instead of `[]` + warning.
2. **Close the behavioral gaps** vs the reference plugin (`PhilippPolterauer/opencode-quotas`) so the rewrite behaves like the original from the user's perspective (modulo the security fixes).

The cycle is **technically complete** (280 tests, all gates green, verified PASS WITH WARNINGS, archived). This handoff is the bridge to the next agent for the follow-up.

---

## Context & Summary

The `opencode-quotas-extended` plugin is a from-scratch rewrite of the PhilippPolterauer reference plugin, executed via a full SDD cycle (propose → spec → design → tasks → 10 apply slices → verify → archive). The hexagonal SOLID architecture is built; 8 providers are registered; the shared pipeline wires footer + `/quotas` command + CLI; 280 tests pass; the secrets-grep gate, build, and typecheck all pass.

**The honest gap**: 8 endpoint URLs are deliberately `TODO(research)` placeholders. The adapters are structurally complete, tested with mocked HTTP, and gracefully return `[]` + a redacted warning when the URL is still the TODO. Production usage of any specific provider requires the URL to be pinned via live capture or docs.

**Plus behavioral gaps** vs the reference plugin that the rewrite may not yet match (e.g., default aggregation groups, polling cache with coalesced refresh, `showUnaggregated` config, `displayMode` simple|detailed|hidden).

This handoff enumerates **all** of the above so the next agent does not relitigate the architecture.

---

## External Artifacts (link, don't duplicate)

### SDD cycle artifacts (engram topic keys)
- Proposal: `sdd/quotas-rewrite/proposal` (`obs #3665`)
- Spec: `sdd/quotas-rewrite/spec` (`obs #3666`)
- Design: `sdd/quotas-rewrite/design` (`obs #3670` candidate)
- Tasks: `sdd/quotas-rewrite/tasks` (`obs #3668`)
- Chain strategy: `sdd/quotas-rewrite/chain-strategy` (`obs #3669`) — stacked-to-main
- Budget reconcile: `sdd/quotas-rewrite/budget-reconcile` (`obs #3671`) — keep 400, consolidate tests
- Apply progress: `sdd/quotas-rewrite/apply-progress` (`obs #3670`) — cumulative Slices 1–10
- Verify report: `sdd/quotas-rewrite/verify-report` (`obs #3675`) — PASS WITH WARNINGS
- Archive report: `sdd/quotas-rewrite/archive-report` (`obs #3676`) — CLOSED
- Cycle complete: `sdd/quotas-rewrite/cycle-complete` (`obs #3674`)
- Decision v1-scope: `decisions/v1-scope` (`obs #3657` updated) — 8 providers, auth.json-first
- Reference (architecture): `reference/opencode-quotas-architecture` (`obs #3655`)
- Reference (auth store): `reference/opencode-auth-store` (`obs #3658`)
- Reference (auth.json key mapping): `reference/auth-json-key-mapping` (`obs #3659`)
- Session pref flight: `sdd/session-preflight` (`obs #3660`)
- Init report: `sdd-init/opencode-quotas-extended` (`obs #3661`)
- Testing capabilities: `sdd/opencode-quotas-extended/testing-capabilities` (`obs #3662`)
- Skill registry: `skill-registry` (`obs #3663`)
- State: `sdd/quotas-rewrite/state` (`obs #3664`)

### Reference plugin (clone for parity research)
- Local clone: `/tmp/opencode-quotas-ref` (shallow clone of `PhilippPolterauer/opencode-quotas@main`)
- Original provider sources (templates for the TODO providers):
  - `src/providers/codex.ts` — OAuth ChatGPT Plus/Pro pattern (template for any `oauth` variant)
  - `src/providers/antigravity/auth.ts` + `provider.ts` — OAuth refresh + multi-endpoint fallback
  - `src/providers/github.ts` (deprecated endpoint — DO NOT port; cited here only for parity)
- Original infrastructure (parity targets):
  - `src/services/quota-service.ts` — `Promise.allSettled` failure isolation
  - `src/services/history-service.ts` — append + reset detection + debounced save
  - `src/services/prediction-engine.ts` — dual-window linear regression
  - `src/services/aggregation-service.ts` — 5 strategies (most_critical/max/min/mean/median)
  - `src/quota-cache.ts` — polling cache with coalesced refresh (gap)
  - `src/ui/footer.ts` + `quota-table.ts` + `progress-bar.ts` — rendering
- Original config: `schemas/quotas.schema.json` (draft-07)
- Original defaults: `src/defaults.ts` (default aggregation groups + gradients)

### Project files (working repo at `/home/metalbolicx/Documents/opencode-quotas-extended`)
- `src/adapters/providers/{zen,go,zai,kimi,minimax,openai,anthropic,gemini}.ts` — 8 adapters (each with a TODO(research) URL constant for its respective `USAGE_URL`)
- `src/domain/{aggregation,prediction,reset}.ts` — pure domain (zero I/O; architecture test enforces)
- `src/adapters/auth/{auth-json-source,env-source,config-source,credential-resolver,redactor}.ts`
- `src/adapters/infra/{json-file-history,config-loader,fetch-http}.ts` + `paths.ts`
- `src/application/report-pipeline.ts` — shared pipeline (resolve → fetch → history → aggregate → predict → render)
- `src/rendering/{status-bar,renderers,index}.ts` + `src/i18n/translator.ts` + `src/i18n/locales/en.json`
- `src/plugin/{index,state,footer-hook}.ts`
- `src/cli/index.ts`
- `commands/quotas.md` — slash command (invokes fixed `opencode-quotas --no-color`)
- `schemas/quotas.schema.json`
- `scripts/{build.ts,check-secrets.sh}`

---

## Endpoint Exploration Plan (the 8 TODO URLs)

For each endpoint, the workflow is: **research → capture → pin → fixture → test → enable**.

### 1. OpenAI platform-usage (API key variant)
- **Current state**: `src/adapters/providers/openai.ts` has TODO(research) for the platform-usage URL. The OAuth/wham/usage path is **pinned** (ChatGPT Plus/Pro).
- **Research path**: OpenAI docs (`https://platform.openai.com/docs/api-reference/usage`) or `https://api.openai.com/v1/usage` with `Authorization: Bearer <OPENAI_API_KEY>`. Note: the `/v1/usage` endpoint is on a deprecation track — OpenAI recommends `/v1/organizations/{org_id}/usage/costs` or similar. Verify the current canonical endpoint before pinning.
- **Auth**: `Authorization: Bearer <OPENAI_API_KEY>`.
- **Expected shape**: `{ object: "list", data: [{ ... }] }` (paginated; need to handle `has_more` / `next_page`).
- **Capture protocol**: Run `curl -H "Authorization: Bearer $OPENAI_API_KEY" '<URL>' | jq .` with a real key (test the user has), redact values, save to `tests/fixtures/providers/openai/platform-usage.json`.
- **Risk**: Endpoints move; paginated; per-org scope.
- **Acceptance**: URL pinned, parsing unit test passes, fixture committed, `fetchQuotas` returns `QuotaData[]`.

### 2. opencode Zen billing
- **Current state**: `src/adapters/providers/zen.ts` has TODO(research) for the opencode.ai billing endpoint.
- **Research path**: Login to `opencode.ai/auth` with the Zen key (stored in `auth.json` under `opencode`). Probe `https://opencode.ai/api/billing/balance` or `https://opencode.ai/api/usage` or similar. The Zen page mentions: "Add credits to your account", "Auto-reload if balance below $5", "Monthly limits". There IS a balance API behind the user dashboard.
- **Auth**: `Authorization: Bearer <zen-key>` (the same key used for `/zen/v1/responses`).
- **Expected shape**: `{ balance: number, currency: 'USD', reset_at: number, monthly_limit: number, monthly_used: number }` (TBD).
- **Capture protocol**: `curl -H "Authorization: Bearer $ZEN_KEY" https://opencode.ai/api/billing/balance | jq .`. If 404, scan `/api/billing/*` paths; the Zen dashboard JS network tab shows the canonical endpoint.
- **Risk**: Reverse-engineered; undocumented; may break with Zen updates.
- **Acceptance**: URL pinned, adapter returns `QuotaData[]` with `category: 'credits'`, fixture committed, integration test passes.

### 3. opencode Go billing
- **Current state**: `src/adapters/providers/go.ts` TODO(research).
- **Same family as Zen** — likely the same `opencode.ai/api/billing/...` endpoint since both Go and Zen are opencode.ai products. Key distinction: the `opencode-go` auth.json key may have a different scope (subscription-only, smaller balance).
- **Research path**: Same as Zen but probe with the `opencode-go` credential. Possibly different endpoint or different path (e.g., `/api/billing/go`).
- **Capture protocol**: Login to opencode.ai, navigate to Go dashboard, capture the balance endpoint from the network tab.
- **Risk**: Same as Zen.
- **Acceptance**: URL pinned, fixture committed, integration test passes.

### 4. z.ai Coding Plan
- **Current state**: `src/adapters/providers/zai.ts` TODO(research).
- **Research path**: Login to `z.ai/manage-apikey/billing` with the `zai-coding-plan` OAuth credential. Probe `https://api.z.ai/api/paas/v4/usage` or `https://api.z.ai/api/coding-plan/usage` or the billing API behind the dashboard. The GLM Coding Plan is documented at `docs.z.ai/devpack/quick-start`.
- **Auth**: Bearer token from the OAuth credential in auth.json (`zai-coding-plan.access`).
- **Expected shape**: `{ plan: 'coding', used: number, limit: number, reset_at: number, windows: [...] }` (TBD).
- **Capture protocol**: `curl -H "Authorization: Bearer $ZAI_TOKEN" https://api.z.ai/api/.../usage`. Network-tab capture from the dashboard.
- **Risk**: OAuth endpoint; rate-limited; z.ai may rotate.
- **Acceptance**: URL pinned, adapter returns `QuotaData[]` with `category: 'subscription'`, fixture committed.

### 5. Kimi / Moonshot
- **Current state**: `src/adapters/providers/kimi.ts` TODO(research).
- **Research path**: Login to `platform.moonshot.ai/console` with the `kimi-for-coding` OAuth credential. Probe `https://platform.moonshot.ai/api/v1/usage` or `https://api.moonshot.ai/v1/usage` or the billing API.
- **Auth**: Bearer token from OAuth credential.
- **Expected shape**: `{ windows: [{ label, used, limit, reset_at }], credits?: number }` (TBD).
- **Capture protocol**: Network-tab capture from the Kimi dashboard.
- **Risk**: OAuth rate-limits; Moonshot may have separate endpoints for coding-plan vs API key.
- **Acceptance**: URL pinned, fixture committed.

### 6. Minimax Coding Plan
- **Current state**: `src/adapters/providers/minimax.ts` TODO(research).
- **Research path**: Login to `platform.minimax.io` with the `minimax-coding-plan` OAuth credential. Probe `https://api.minimax.io/v1/usage` or `https://platform.minimax.io/api/usage` or the billing API.
- **Auth**: Bearer token from OAuth credential.
- **Expected shape**: `{ windows: [{ label, used, limit, reset_at }] }` (TBD).
- **Capture protocol**: Network-tab capture.
- **Risk**: Same as the others.
- **Acceptance**: URL pinned, fixture committed.

### 7. Anthropic API
- **Current state**: `src/adapters/providers/anthropic.ts` TODO(research).
- **Research path**: The Anthropic API has admin endpoints at `https://api.anthropic.com/v1/organizations/{org_id}/usage` (requires admin key with `usage:read` scope). NOT `/v1/usage` (doesn't exist). The org_id must be supplied — extend the adapter to accept it via config.
- **Auth**: `x-api-key: <ANTHROPIC_API_KEY>` + `anthropic-version: 2023-06-01`.
- **Expected shape**: `{ data: [{ date_window, model, input_tokens, output_tokens, ... }], has_more: boolean, next_page: string }` (paginated).
- **Capture protocol**: `curl -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" https://api.anthropic.com/v1/organizations/<org_id>/usage?limit=31`.
- **Risk**: Requires admin scope; not available to all account tiers. The adapter config needs `orgId` — document this and add a fail-fast validation.
- **Acceptance**: URL pinned, org-id config support, pagination handling, fixture committed.

### 8. Google Gemini
- **Current state**: `src/adapters/providers/gemini.ts` TODO(research).
- **Research path**: For Google AI Studio (API key), aggregate usage is **not exposed** via the public API. The option per the design is **per-request rate-limit headers** — for that, no aggregate endpoint is needed; the adapter must probe a 1-token request and capture the headers. The endpoint is `https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent` (with a body requesting 1 token).
- **Auth**: `x-goog-api-key: <GEMINI_API_KEY>` (or `?key=...` query string).
- **Expected shape**: Rate-limit headers in the response (e.g., `x-ratelimit-remaining-requests`, `x-ratelimit-remaining-tokens`, `x-ratelimit-reset`).
- **Capture protocol**: `curl -H "x-goog-api-key: $GEMINI_API_KEY" -X POST https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent -d '{"contents":[{"parts":[{"text":"hi"}]}],"generationConfig":{"maxOutputTokens":1}}' -D -` (capture headers).
- **Risk**: Probes consume a token; Gemini may not always return headers; rate-limit semantics differ per model.
- **Acceptance**: Adapter reads rate-limit headers, returns `QuotaData[]` representing rpm/rpd windows, fixture committed (the HTTP response with headers).

### General capture protocol (all 8)
1. Document the chosen URL + auth headers in a `notes/<provider>-endpoint.md` capture note.
2. Run a real probe with the user's credential (real-time, masked in any shared output).
3. Redact the response and save to `tests/fixtures/providers/<id>/usage.json` (or `headers.txt` for rate-limit headers).
4. Replace the TODO(research) constant with the pinned URL.
5. Replace the `if URL is TODO → return []` guard with the real parse path.
6. Write/update a unit test that asserts the parsing maps the fixture into `QuotaData[]`.
7. Verify the integration test (`tests/integration/pipeline.test.ts`) still passes.
8. Update README "open-issues" section to remove the TODO entry.

### Per-endpoint safety gate
- **Never commit secrets into fixtures.** The capture script must redact `key`, `access`, `refresh`, `token` recursively to `****` before writing. The `scripts/check-secrets.sh` gate must continue to exit 0.
- **Never test against a live endpoint in the unit test suite.** All HTTP remains mocked via `vi.fn()` / `vi.mock`. Live capture is a one-time, manual step.

---

## Gap Analysis vs Reference Plugin

What the original `PhilippPolterauer/opencode-quotas` does that the rewrite **does not yet match** (modulo the security fixes that EXCLUDED the hardcoded-secret Antigravity and the deprecated GitHub Copilot).

### Behavioral gaps (must close to match the reference)

| # | Gap | Reference location | Our state | Action |
|---|---|---|---|---|
| 1 | **Default aggregation groups** | `src/defaults.ts:25-53` defines built-in groups: `ag-flash`, `ag-pro`, `ag-premium` (patterns) + `codex-smart` (sources). These auto-aggregate raw quotas. | `src/defaults.ts` (or equivalent) does NOT define provider-aware defaults for Zen/Go/z.ai/Kimi/Minimax. | Add default aggregation groups for the 5 coding-plan providers (e.g., `opencode-zen-monthly`, `zai-coding-plan-weekly`, `kimi-daily`, `minimax-monthly`). Strategy: `most_critical`. |
| 2 | **Polling cache with coalesced refresh** | `src/quota-cache.ts` — interval-based polling with per-provider in-flight coalescing so concurrent footer calls don't trigger N fetches. | `src/application/report-pipeline.ts` fetches on every call (no caching). For high-frequency hook calls, this is N×8 requests per message. | Add a `QuotaCache` adapter implementing a `CacheSource` port with interval-based refresh + in-flight coalescing. Mirror `src/quota-cache.ts` from the reference (cleaned up). |
| 3 | **`showUnaggregated` config** | `src/constants.ts` + `src/services/quota-service.ts:217-275` — controls whether to show raw quotas that didn't match any aggregation group. | Not exposed in `schemas/quotas.schema.json`. | Add `showUnaggregated: boolean` (default `false`) to config schema + render logic. |
| 4 | **`displayMode` config (simple\|detailed\|hidden)** | `src/utils/validation.ts` + `src/ui/footer.ts` — original supports three modes. | We have `compact` (footer) vs `full` (command/CLI). The original's tri-state is richer. | Decide: keep our binary `compact`/`full`, or expand to `simple\|detailed\|hidden` to match the reference. If the latter, document the mapping (`simple` → compact, `detailed` → full, `hidden` → no footer). |
| 5 | **Provider-aware `providerId` filter in pattern matching** | `src/services/quota-service.ts:341-384` — `aggregatedGroups[].providerId` restricts pattern matching to a single provider. | We have this in the config (per the spec) but verify the implementation honors it correctly. | Add unit tests asserting that `providerId: 'antigravity'` restricts pattern matching to Antigravity-only quotas. (Note: Antigravity is excluded; substitute with `openai` or another provider.) |
| 6 | **CLI `--provider` and `--model` filter behavior** | Original `src/cli.ts:23-31` — filters by provider+model ID. | We have `--provider` and `--model` in the CLI but the report-pipeline filtering is currently minimal. | Verify the report-pipeline filters by `providerId` and `modelId` correctly. Add a focused test. |
| 7 | **Original's `company` info / `info` field** | Reference carries `info: string` on `QuotaData` (e.g., "!!", "unlimited", "balance") and renders it as a column. | We have `QuotaData.info` and the `info` column in the renderer (per the design), but verify the providers populate it correctly. | Add unit tests asserting each provider's `info` field is populated appropriately. |
| 8 | **Original's `window` field** | `QuotaData.window: string` (e.g., "5h window", "Monthly") renders as a column. | We have `window` field and column. Verify each provider populates it. | Add unit tests. |
| 9 | **Original's `details` field** (deprecated) | `src/interfaces.ts:31` — `@deprecated` `details` field. | We do NOT have this. | Skip (deprecated). |
| 10 | **Multi-endpoint fallback for Antigravity** | `src/providers/antigravity/auth.ts` — hardcoded `client_secret` + 3 fallback endpoints. | Antigravity is excluded for security. The fallback pattern is reusable but not currently needed. | Skip (Antigravity excluded). |
| 11 | **Original's `enableExperimentalGithub` flag** | Gated GitHub Copilot provider behind a config flag. | GitHub Copilot is excluded (deprecated endpoint). | Skip. |
| 12 | **Antigravity `warning` indicators (`!`, `!!`)** | `src/providers/antigravity/provider.ts:70-73` — warning at 20% remaining (`!`) and 5% remaining (`!!`). | Not implemented. | Optional: add `info: '!!'` for any provider at <5% remaining. |
| 13 | **Original's `null` for `limit` (unlimited)** | `QuotaData.limit: number \| null` — `null` = unlimited. | We have this. | ✓ |
| 14 | **Original's `predictedReset` field** | `QuotaData.predictedReset: string` (e.g., "in 12m (predicted)") rendered as a column. | We have `ettl` (Estimated Time To Limit) per the design. The original's `predictedReset` is the same concept (slightly different name). | Verify the ETTL rendering matches the original's `predictedReset` text format. |
| 15 | **Original's `progressBar.gradients` defaults** | `[{threshold:0.5,color:'green'},{threshold:0.8,color:'yellow'},{threshold:1.0,color:'red'}]` | We have the same defaults. | ✓ |
| 16 | **Original's `table.columns` default** | `["status","name","percent","bar","reset","ettl"]` | We have the same default. | ✓ |
| 17 | **Original's `enableExperimentalGithub` config** | `schemas/quotas.schema.json` | Removed (Copilot excluded). | Skip. |
| 18 | **CLI color precedence** | `FORCE_COLOR` > `NO_COLOR` > config > TTY | We have the same. | ✓ |

### Architectural deltas (intentional, not gaps)

The rewrite **intentionally ** does the following **better than the reference**:

- **No hardcoded secrets** (the reference ships a Google `client_secret` in source — CRITICAL). Skip Antigravity.
- **auth.json-first credential resolver** with variant-aware `api`/`oauth`/`wellknown` (the reference scattered OAuth reads across providers).
- **Recursive secret redaction** on every credential log message (the reference only redacted in some places).
- **Hexagonal SOLID architecture** (the reference is a vendored module-per-feature; ours is core/ports/adapters with strict I/O boundaries and architecture tests).
- **i18n from day zero** (the reference hardcoded English strings).
- **JSON + Markdown renderers** (the reference had only the ANSI table).
- **Ajv config validation** (the reference used a simpler schema validator).
- **Coverage thresholds** (the reference didn't have them).
- **8 providers** vs the reference's 3.

---

## Suggested Skills for the Next Agent

The follow-up cycle (`pin-provider-endpoints`) should load:

- **`sdd-propose`** — for the new change proposal (justifying the new cycle).
- **`sdd-spec`** — for the new spec (8 endpoint captures + gap closures).
- **`sdd-design`** — for the design (URL pinning strategy + polling cache + default aggregation groups).
- **`sdd-tasks`** — for the task breakdown (one per endpoint + gaps).
- **`sdd-apply`** — for implementation (one slice per endpoint).
- **`sdd-verify`** — for verification.
- **`sdd-archive`** — for archive.
- **`work-unit-commits`** — reviewable commit slices.
- **`chained-pr`** — stacked-to-main chained PRs.
- **`good-comments`** — comments that emphasize *why*/*how* over *what*.
- **`diagnose`** — for debugging endpoint shape mismatches.
- **`web-coder`** — for endpoint research (HTTP, REST semantics, auth headers).
- **`customize-opencode`** — for opencode plugin conventions.
- **`context7_resolve-library-id`** + **`context7_query-docs`** — for fetching current provider docs at research time.

Do NOT load: `commit-process`, `review`, `skill-improver`, `skill-creator` (not relevant to this cycle).

---

## Acceptance Criteria for the Next Cycle

The next cycle is done when:

1. **All 8 TODO(research) URL constants are pinned** with real URLs in `src/adapters/providers/*.ts`. Catch the `TODO(research)` pattern with `grep -RE "TODO\\(research\\)" src/` and assert exit 1.
2. **Each provider's `fetchQuotas` returns real `QuotaData[]`** for a real credential (manual smoke test per provider; document the result in a `notes/provider-smoke-tests.md`).
3. **All 8 provider fixtures are committed** in `tests/fixtures/providers/<id>/`.
4. **The integration test** (`tests/integration/pipeline.test.ts`) is updated to assert that all 8 providers contribute rows when fully wired (with the real URLs and mocked responses).
5. **Default aggregation groups** are added for the 5 coding-plan providers in `src/adapters/providers/defaults.ts` (or similar).
6. **Polling cache with coalesced refresh** is implemented as a `CacheSource` port + adapter, with focused tests.
7. **`showUnaggregated` config** is added to the schema + render logic.
8. **280+ tests pass** (existing) + **+20 new tests** (providers + cache + gap coverage) = **300+ total**.
9. **`bun run test`, `bun run typecheck`, `bun run build`, `bash scripts/check-secrets.sh`** all green.
10. **README open-issues section** is updated to reflect the closed gaps.
11. **Slice budget respected**: each apply slice ≤400 lines (the consolidate-tests directive still applies).

### Risks for the next cycle

- **Reverse-engineered endpoints may break** without notice. The adapters must fail gracefully (return `[]` + warning) — DO NOT crash the chat on a provider 404.
- **Antigravity** stays excluded — the hardcoded secret must never enter the source.
- **GitHub Copilot** stays excluded — the endpoint is deprecated.
- **The polling cache** must not introduce a memory leak (prune history + bound cache size).
- **OAuth refresh storms** — the OAuth helper from Slice 5 already has single-flight, but test it under concurrency.

### Reference: the existing `sdd/quotas-rewrite` artifacts

When proposing the new change, the next agent should reference (link in the proposal) the existing cycle's artifacts to avoid duplicating them. The new `pin-provider-endpoints` change is a **follow-up** — it inherits the architecture locked in `sdd/quotas-rewrite/design` and only fills the TODO gaps + closes the behavioral gaps listed above.

---

## Suggested Skills for the Next Agent

Same as above. (Listed once in the previous section.)
