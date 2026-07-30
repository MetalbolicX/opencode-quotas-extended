Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

# Tasks: Add ReScript Interfaces & Type Safety

## Review Workload Forecast

Estimate: 1,000+ lines, 50+ files; high risk; PR per phase.

## Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | Domain | 1 | build/tests | N/A: types | `src/testing`, `src/domain` |
| 2 | Providers | 2 | build/provider tests | CLI help | Providers/Cli/rendering |
| 3 | JSON | 3 | build/config tests | `pnpm test` | Infra decoders |
| 4 | Node FFI | 4 | build | CLI help | `src/bindings/Node.*` |
| 5 | Interfaces | 5 | build/affected tests | N/A: API only | listed `.resi` |
| 6 | Barrels/gates | 6 | all gates | CLI help | barrels/architecture tests |

## Phase 1: Test Factory Extraction + Domain `.resi`

- [x] 1.1 RED: Add `src/testing/DomainFixturesTests.res`; assert four factories/shapes.
- [x] 1.2 GREEN: Create `src/testing/DomainFixtures.res`/`.resi` with the four named factories.
- [x] 1.3 REFACTOR: Remove factories from `src/domain/{Types,Aggregation}.res` and `Domain.res` exports.
- [x] 1.4 RED: Add `tests/architecture/resi-coverage.test.ts` for domain consumers.
- [x] 1.5 GREEN: Create `.resi` for `Types`, `Aggregation`, `Prediction`, `Reset`, `AggregationDefaults`, `Domain`.
- [x] 1.6 REFACTOR: Update all test imports to `DomainFixtures`; run build and `pnpm test`.

## Phase 2: Provider Type Unification

> **Phase 2a completed** (this apply session): unified `quotaData` data shape. Providers produce `Domain.quotaData` with `reset: option<Date.t>` and camelCase windows. `QuotaData.res` deleted. Renderers `Obj.magic` removed.

- [x] 2a.1: Add `#rolling1h` to domain `windowType` + converters (Types.res, Types.resi)
- [x] 2a.2: Delete `src/Providers/QuotaData.res`; update `Providers.res` barrel
- [x] 2a.3: Convert OpenAI, Gemini, Minimax, Anthropic to `Domain.quotaData` (reset: `Date.t`, windows: camelCase); update CodingPlanParse + test file; update Zen/Go/Zai/Kimi local `quotaProvider` types
- [x] 2a.4: Update `Registry.res` `sharedProvider.fetchQuotas` to `array<Domain.quotaData>` (private_coerce kept for 2b)
- [x] 2a.5: Remove 9× `Obj.magic`/`%raw Date.parse` from Renderers.res (`fmtReset`, `windowLabelText`, `windowToStr`, jsonRenderer reset)
- [x] 2a.6: Full gate — `pnpm res:build` clean, 655/655 tests green, Renderers warning #11 gone

- [x] 2b: Provider type identity — unified `Provider.quotaProvider` (Phase 2b complete)
  - [x] 2b.1: All 8 providers return `Provider.quotaProvider` (local types deleted)
  - [x] 2b.2: `Registry.res` — removed `sharedProvider`/`private_coerce`, uses `Provider.quotaProvider` directly
  - [x] 2b.3: `ReportPipeline.res` — replaced local `quotaProvider` with `type quotaProvider = Provider.quotaProvider`
  - [x] 2b.4: `Cli.res` — removed 4× `Obj.magic`, updated filter/render functions
  - [x] 2b.5: Created 8 provider `.resi` files
  - [x] 2b.6: Full gate — `pnpm res:build` exit 0, 655 tests, `private_coerce`=0, Cli `Obj.magic`=0

## Phase 3: Manual JSON Decoders

- [x] 3.1 RED: Add `ConfigLoaderTests.res` cases for partial config and `aggregatedGroups`.
- [x] 3.2 GREEN: Add private `JSON.t` decoders in `ConfigLoader.res`; replace 11 of 12 `%raw` accesses (1 schema stays); Obj.magic removed. Note: 6 `%raw` calls remain for booleans + `progressBar` + `aggregatedGroups` because JSON module lacks `Bool` variant in ReScript 12.3.0.
- [x] 3.3 REFACTOR: Replace four `JsonFileHistory.res` `%raw` conversions with typed decoders; run build/tests. All 4 replaced.

## Phase 4: Node FFI Externals

- [x] 4.1 RED: Add an architecture contract test for four targeted `Node.res` bindings.
- [x] 4.2 GREEN: Replace them with `@val`/`@scope` externals; create `src/bindings/Node.resi`.
- [x] 4.3 REFACTOR: Run `rescript build` and CLI `--help`.

## Phase 5: Auth/Cli/Rendering `.resi`

- [x] 5.1 RED: Extend `resi-coverage.test.ts` for `src/Infra/{FetchHttp,JsonFileHistory,Paths,ConfigLoader}`, `src/Auth/{Credential,CredentialResolver,AuthJsonSource,EnvSource,ConfigSource,Redactor,ProviderKeys}.res`, `src/Cli/{Cli,ParseArgs,Messages}`, `src/rendering/{Renderers,Colors}`, `src/i18n/Translator.res`.
- [x] 5.2 GREEN: Create those interfaces; expose only cross-module APIs.
- [x] 5.3 REFACTOR: Compile and run affected ReScript tests.

### Phase 5a: ParseArgs + Renderers Obj.magic Reduction (apply session)

- [x] 5a.1 ParseArgs.res: type `node:util.parseArgs` FFI with `@get` externals; remove 7× `Obj.magic`
- [x] 5a.2 Renderers.res: remove `Obj.magic(null)` sentinel; ConfigLoader.res: fix `progressBar` `== null` to treat both null and undefined as absent

### Phase 5b: %raw Cleanup + High-Value .resi (this apply session)

**%raw reduction (A):**
- [x] Paths.res: `%raw("process.env")` → `Node.processEnv`
- [x] Cli.res: `Promise.resolve(%raw("undefined"))` → `Promise.resolve()`
- [x] Anthropic.res: `%raw("process.cwd()")` → `Node.processCwd()`; `err && err.status` → typed `@get external errorStatus`; `Object.assign(new Error(...), {status: 403})` → `@new external makeAdminError`
- [x] FetchHttp.res: `Promise.reject(%raw("new Error(...)"))` → `@new external makeFetchError`; `Promise.resolve(%raw("null"))` → `Promise.resolve(JSON.Null)`
- [x] Gemini.res: 2× `Promise.reject(%raw("new Error(... )"))` → `@new external makeGeminiError`
- [x] CredentialResolver.res: `%raw("process.cwd()")` → `Node.processCwd()`
- [x] Minimax.res: `lastIndexOf` raw → typed workaround using `String.slice` + `Js.String.lastIndexOf`
- [~] OAuth.res: `Number(err && err.status)` — kept (requires `exn` property access; complex to type without breaking exn semantics)
- **Result: 8 remaining (was ~19) — ≤17 target MET; 58% reduction (goal: ≥70%)**

**High-value .resi files (B):**
- [x] Created `src/Infra/Paths.resi` — `getDataHome`, `getAuthJsonPath`, `getHistoryPath`
- [x] Created `src/Cli/ParseArgs.resi` — `parsedArgs`, `parse`
- [x] Created `src/rendering/Renderers.resi` — `translator`, `progressBarConfig`, `renderContext`, `renderer`, `selectRenderer`
- [x] Created `src/Cli/Cli.resi` — `runResult`, `run`, `main`, `usageText`
- [x] Created `src/Infra/FetchHttp.resi` — `logger`, `httpRequest`, `requestOptions`, `fetchInit`, `httpClient`, `make`, `request`, `installRealFetch`, `noopLogger`, `fetchImpl` (test override)
- [x] Created `src/Infra/JsonFileHistory.resi` — `deps`, `historyStore`, `store`, `make`
- [x] Created `src/Infra/ConfigLoader.resi` — `logger`, `progressBar`, `progressBarPartial`, `aggregationGroup`, `anthropicConfig`, `quotasConfig`, `partialConfig`, `loadConfig`, `resolveAnthropicOrgId`, `defaults`, `depsRef`, `ConfigValidationError` (depsRef+exception included for test compatibility)

**Architecture test update (C):**
- [x] 5b.1: Extend `tests/architecture/resi-coverage.test.ts` to assert .resi existence for new modules (done in Phase 6)

## Phase 6: Barrel `.resi` and Verification

- [x] 6.1 REFACTOR: Create/update `src/{domain/Domain,Providers/Providers,Auth/Auth,Infra/Infra}.resi`.
  - [x] `src/Infra/Infra.resi` — mirrors `getDataHome`, `getAuthJsonPath`, `getHistoryPath`, `request`, `make`, `loadConfig`, `resolveAnthropicOrgId`
  - [x] `src/Auth/Auth.resi` — `include Credential` (via explicit type re-declarations); `Credential.resi` created to support it
  - [x] `src/Providers/Providers.res` confirmed comment-only — no `.resi` needed
- [x] 6.2 Cross-module `.resi` files:
  - [x] `src/rendering/Colors.resi` — `ansiColor`, `colorMap`, `validColorNames`, `dim`
  - [x] `src/i18n/Translator.resi` — `translator`, `createI18nTranslator`, `enCatalog`
  - [x] `src/Cli/Messages.resi` — `formatNoSubscriptions`, `formatNoCredentialsForProvider`, `formatProviderFetchErrors`, `formatMissingAuthJson`
  - [x] `src/bindings/Node.resi` — full surface of all externals
  - [x] `src/Auth/CredentialResolver.resi` — `resolve` function (cross-module consumed by providers)
- [x] 6.3 RED/GREEN: Architecture regression-guard test `tests/architecture/type-safety-guards.test.ts`:
  - [x] Obj.magic guard: asserts 0 occurrences in `src/**/*.res` (excluding `*Tests.res`)
  - [x] %raw budget: asserts ≤ 12 occurrences in `src/**/*.res` (excluding `*Tests.res`) — current: 9
  - [x] .resi coverage: asserts all cross-module modules have matching `.resi` (35 modules)
- [x] 6.4 GATE: `pnpm res:build` (0 warnings), `pnpm test` (690/690), `pnpm typecheck` (exit 0), `pnpm build` (rolldown bundle 95.25 kB)
- [x] **Revert note**: an over-reach that aliased the canonical `src/ports/*.resi` contracts to implementation modules (inverting DIP) was reverted. The `src/ports/*.resi` remain documented port interfaces (interface-only, skipped by the ReScript compiler) — they were never broken; a thin top-level `src/Provider.{res,resi}` pair was created instead because interface-only `.resi` are skipped unless paired with a `.res`.

 Threat matrix: N/A.
