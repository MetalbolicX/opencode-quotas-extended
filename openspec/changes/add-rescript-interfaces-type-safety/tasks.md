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

- [ ] 4.1 RED: Add an architecture contract test for four targeted `Node.res` bindings.
- [ ] 4.2 GREEN: Replace them with `@val`/`@scope` externals; create `src/bindings/Node.resi`.
- [ ] 4.3 REFACTOR: Run `rescript build` and CLI `--help`.

## Phase 5: Auth/Cli/Rendering `.resi`

- [ ] 5.1 RED: Extend `resi-coverage.test.ts` for `src/Infra/{FetchHttp,JsonFileHistory,Paths,ConfigLoader}`, `src/Auth/{Credential,CredentialResolver,AuthJsonSource,EnvSource,ConfigSource,Redactor,ProviderKeys}.res`, `src/Cli/{Cli,ParseArgs,Messages}`, `src/rendering/{Renderers,Colors}`, `src/i18n/Translator.res`.
- [ ] 5.2 GREEN: Create those interfaces; expose only cross-module APIs.
- [ ] 5.3 REFACTOR: Compile and run affected ReScript tests.

## Phase 6: Barrel `.resi` and Verification

- [ ] 6.1 REFACTOR: Create/update `src/{domain/Domain,Providers/Providers,Auth/Auth,Infra/Infra}.resi`.
- [ ] 6.2 RED: Add an architecture test requiring `%raw` reduction ≥70% and `Obj.magic` ≥80% in `src/` (excluding `*Tests.res`).
- [ ] 6.3 GREEN: Remove remaining in-scope unsafe constructs until thresholds pass; preserve explicitly out-of-scope test hacks.
- [ ] 6.4 REFACTOR: Run `rescript build`, `pnpm test`, `pnpm typecheck`, `pnpm build`, CLI smoke.

Threat matrix: N/A.
