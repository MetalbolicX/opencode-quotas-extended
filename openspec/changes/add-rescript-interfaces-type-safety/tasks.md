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

- [ ] 1.1 RED: Add `src/testing/DomainFixturesTests.res`; assert four factories/shapes.
- [ ] 1.2 GREEN: Create `src/testing/DomainFixtures.res`/`.resi` with the four named factories.
- [ ] 1.3 REFACTOR: Remove factories from `src/domain/{Types,Aggregation}.res` and `Domain.res` exports.
- [ ] 1.4 RED: Add `tests/architecture/resi-coverage.test.ts` for domain consumers.
- [ ] 1.5 GREEN: Create `.resi` for `Types`, `Aggregation`, `Prediction`, `Reset`, `AggregationDefaults`, `Domain`.
- [ ] 1.6 REFACTOR: Update all test imports to `DomainFixtures`; run build and `pnpm test`.

## Phase 2: Provider Type Unification

- [ ] 2.1 RED: Update `src/Providers/RegistryTests.res`; require `array<Provider.quotaProvider>`, no coercion.
- [ ] 2.2 GREEN: Return `Provider.quotaProvider` from `OpenAI`, `Zen`, `Go`, `Zai`, `Kimi`, `Minimax`, `Anthropic`, `Gemini`.
- [ ] 2.3 REFACTOR: Remove `sharedProvider`/`private_coerce` from `Registry.res`; update `QuotaData.res`, `CodingPlanParse.res`, `Filter.res`, `ReportPipeline.res`.
- [ ] 2.4 REFACTOR: Remove provider-boundary `Obj.magic` from `Renderers.res`, `Cli.res`, `ParseArgs.res`; add `src/Providers/{OpenAI,Zen,Go,Zai,Kimi,Minimax,Anthropic,Gemini,Registry}.resi`.
- [ ] 2.5 REFACTOR: Run build and provider/CLI/rendering tests.

## Phase 3: Manual JSON Decoders

- [ ] 3.1 RED: Add `ConfigLoaderTests.res` cases for partial config and `aggregatedGroups`.
- [ ] 3.2 GREEN: Add private `JSON.t` decoders in `ConfigLoader.res`; replace its 12 `%raw` accesses and four `Obj.magic` calls.
- [ ] 3.3 REFACTOR: Replace four `JsonFileHistory.res` `%raw` conversions with typed decoders; run build/tests.

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
