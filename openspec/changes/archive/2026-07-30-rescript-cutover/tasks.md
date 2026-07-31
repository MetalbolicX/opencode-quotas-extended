# Tasks: ReScript Production Cutover

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated authored changed lines | ~1,300–2,000 (deletions counted; generated `.res` and lockfile excluded) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | WU-1 → WU-2 → WU-3 → WU-4a → WU-4b → WU-5 → WU-6 → WU-7 |
| Delivery strategy | stacked-to-main |
| Chain strategy | stacked-to-main |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

WU-4 and WU-6 are budget gates: split into WU-4c or WU-6a+ when authored additions plus deletions exceed 400 lines; the orchestrator must ask before applying that split. Each PR rebases onto the latest `main` after its predecessor merges. No worktrees are needed.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---:|---|---|---|
| WU-1 | Deterministic schema/catalog codegen | 1 | `node scripts/codegen.test.mjs` | `pnpm res:build` | Codegen, generated imports, and `.gitignore` |
| WU-2 | Lifecycle ordering and fail-fast build | 2 | `pnpm prebuild` | `pnpm build` + CLI help | `package.json` lifecycle entries |
| WU-3 | Aggregate compiled ReScript tests | 3 | `node scripts/run-tests.test.mjs` | `pnpm test:res` | Runner and `test:res` only |
| WU-4a | Six architecture guards | 4 | `pnpm test:res` | Compiled guard modules | Guard modules only |
| WU-4b | Parity gaps and receipt | 5 | `pnpm test` + `pnpm test:res` in parallel | `node dist/cli/index.js --help` | New parity tests |
| WU-5 | Archive 46 TS files while Vitest runs | 6 | `pnpm test` + `pnpm test:res` | Build and CLI smoke | `legacy/` moves plus test import retargets |
| WU-6 | Remove Vitest and switch `pnpm test` | 7 | `pnpm test` | Build, install, CLI smoke | Package/test-tool deletion slices |
| WU-7 | Rewrite operational documentation | 8 | `pnpm test` + `pnpm build` | CLI smoke | `README.md` and `CLAUDE.md` |

## Phase 1: Asset Foundation

### WU-1 — Add deterministic asset codegen (depends on: none)

- **Objective:** Generate the schema and English catalog from canonical JSON, with no build wiring yet.
- **Files:** **Created** `scripts/codegen.mjs`, `tests/unit/scripts/codegen.test.ts`; **created/generated and git-ignored** `src/Infra/ConfigLoader/Schema.res`, `src/i18n/Translator/EnCatalog.res`; **modified** `.gitignore`, `src/Infra/ConfigLoader.res`, `src/i18n/Translator.res`. NOTE: generated files use subdirectory placement (`ConfigLoader/Schema.res`, `Translator/EnCatalog.res`) to avoid ReScript namespace self-reference conflict — module names remain `ConfigLoader.Schema` and `Translator.EnCatalog`.
- **Tasks:** `[x] RED` test schema/locale emission, idempotence, `--check`, round-trip equality, and deliberate drift exit `1`; `[x] GREEN` implement sorted-key, byte-stable generation and generated-module imports.
- **Validation:** `node scripts/codegen.test.mjs`, two `node scripts/codegen.mjs` runs, and `node scripts/codegen.mjs --check` exit `0`; drift fixture exits `1`; `pnpm res:build` and `pnpm test` exit `0`.
- **Map-to-spec:** REQ-CODEGEN-1..6 (schema, locale, ignore, idempotence, round-trip/drift, consumers); realizes every asset-codegen Given/When/Then scenario. **Estimate:** ~200 lines. **Commit:** `feat(scripts): add deterministic codegen for schema and catalog assets (WU-1)`. **Worktree:** none; `feat/rescript-cutover-codegen` targets `main`.

### WU-2 — Wire codegen into the build lifecycle (depends on: WU-1)

- **Objective:** Make every production build and direct ReScript build run codegen before compilation, and bootstrap fresh installs.
- **Files:** **Modified** `package.json`; temporary process-order/failure-short-circuit fixtures are created only by the test harness and are not committed.
- **Tasks:** `[ ] RED` exercise hook order and prove a failed `res:build` prevents rolldown; `[ ] GREEN` add `codegen: node scripts/codegen.mjs`, `prebuild: pnpm run codegen && pnpm run res:build`, `preres:build: pnpm run codegen`, and `postinstall: pnpm run codegen` while leaving `test` as Vitest.
- **Validation:** `pnpm codegen`, `pnpm prebuild`, `pnpm res:build`, `pnpm build`, and `pnpm postinstall` exit `0`; the failure fixture exits non-zero and never invokes rolldown; `pnpm test` exits `0`; `node dist/cli/index.js --help` exits `0`.
- **Map-to-spec:** REQ-PIPELINE-1..4 and CODEGEN-6; realizes build order, manual `res:build`, fresh-install, fail-fast, and CLI-smoke scenarios while preserving **INV-1/INV-2**. **Estimate:** ~30–70 lines. **Commit:** `build: wire codegen into lifecycle hooks`. **Worktree:** none; `feat/rescript-cutover-codegen-wire` targets `main`.

## Phase 2: ReScript Test Runner

### WU-3 — Add the aggregate runner (depends on: WU-2)

- **Objective:** Discover compiled ReScript test modules, run each in an isolated Node child, and aggregate every result without changing Vitest.
- **Files:** **Created** `scripts/run-tests.mjs`, `scripts/run-tests.test.mjs`; **modified** `package.json` with `test:res` only.
- **Tasks:** `[ ] RED` cover pass, non-zero/crash, signal, timeout, zero files, summary attribution, and argument-array/no-shell execution; `[ ] GREEN` implement sorted discovery of both required suffixes, 30-second timeout with `RES_TEST_TIMEOUT_MS`, inherited stdio, run-all aggregation, and non-zero failure exit.
- **Validation:** `node scripts/run-tests.test.mjs`, `pnpm res:build`, and `pnpm test:res` exit `0`; zero-file and failing-child fixtures exit non-zero and name the file; `pnpm test` exits `0`.
- **Map-to-spec:** REQ-TEST-1..5 and the applicable child-process threat-matrix cases; realizes discovery, zero-match, all-pass, crash/timeout, one-failure, summary, and parallel Vitest scenarios. **Estimate:** ~150 lines. **Commit:** `test: add aggregate ReScript test runner`. **Worktree:** none; `feat/rescript-cutover-runner` targets `main`.

## Phase 3: Parity Proof

### WU-4a — Port architecture guards (depends on: WU-3)

- **Objective:** Port all six applicable architecture guards before any archive or Vitest removal.
- **Files:** **Created** `src/architecture/BuildScriptTests.res`, `src/architecture/CheckSecretsTests.res`, `src/architecture/DomainPurityTests.res`, `src/architecture/ResiCoverageTests.res`, `src/architecture/ScaffoldTests.res`, `src/architecture/TypeSafetyGuardsTests.res`.
- **Tasks:** `[ ] RED` mirror each existing guard; `[ ] GREEN` use ReScript test APIs plus `Node.fs`/`Node.execSync`; remove the `src/cli/index.ts` assertion and allow the future committed `legacy/` tree in the scaffold guard. Do not port `vitest-thresholds` or `domain.parity`.
- **Validation:** `pnpm res:build`, `pnpm test:res`, `pnpm test`, and `pnpm typecheck` exit `0`; guard output is attributable per file.
- **Map-to-spec:** REQ-TEST-1, TEST-4, TEST-5 and **INV-1**; realizes the architecture guard and no-deletion-through-phase-4 constraints. **Estimate:** ~300 lines. **Commit:** `test: port architecture guards to ReScript`. **Worktree:** none; `feat/rescript-cutover-arch-tests` targets `main`.

### WU-4b — Close parity gaps and issue the receipt (depends on: WU-4a)

- **Objective:** Add 5–10 unit gaps, three integration tests, and evidence for five uncertain-parity production modules before the irreversible boundary.
- **Files:** **Created** `src/application/ReportPipelineTests.res`, `src/Providers/ProviderFailureTests.res`, `src/Infra/ConfigLoaderCodegenTests.res`, `src/i18n/TranslatorCodegenTests.res`, `src/rendering/RenderersParityTests.res`, `src/integration/BuildPipelineIntegrationTests.res`, `src/integration/RunnerIntegrationTests.res`, `src/integration/CliIntegrationTests.res`; **modified** only existing ReScript tests needed to close mapped gaps. Verify `src/application/ReportPipeline.res`, `src/Infra/ConfigLoader.res`, `src/i18n/Translator.res`, `src/Cli/Cli.res`, and `src/rendering/Renderers.res` explicitly.
- **Tasks:** `[ ] RED` translate uncovered Vitest scenarios and the three integration flows; `[ ] GREEN` preserve assertions and add no production behavior change; `[ ]` run both runners concurrently from one clean install and record Vitest pass count, ReScript pass count, and zero failures in the PR/verify receipt.
- **Validation:** `pnpm test` and `pnpm test:res` run in parallel and each exit `0` with matching coverage-analysis counts; `pnpm typecheck`, `pnpm build`, `node dist/cli/index.js --help`, and `bash scripts/check-secrets.sh` exit `0`. Missing receipt blocks WU-5 and WU-6. If this diff exceeds 400 authored lines, create **WU-4c** for integration tests before merging.
- **Map-to-spec:** REQ-TEST-5 and **INV-1/INV-2**, plus PIPELINE-4 and CODEGEN-6 integration scenarios; realizes the explicit parity gate. **Estimate:** ~300 lines (WU-4c contingency: ~150). **Commit:** `test: close ReScript parity gaps and record receipt`. **Worktree:** none; `feat/rescript-cutover-test-gaps` targets `main`.

## Phase 4: Guarded Cutover

### WU-5 — Archive TypeScript and keep the pre-removal Vitest receipt (depends on: WU-4b parity confirmed)

- **Objective:** Move the verified 46-file TypeScript source set to `legacy/` while retaining a green Vitest run by retargeting its imports to the preserved archive.
- **Files:** **Moved-to-legacy** (preserve each relative path): `src/adapters/auth/{auth-json-source,config-source,credential-resolver,env-source,provider-keys,redactor}.ts`; `src/adapters/infra/{config-loader,fetch-http,json-file-history,paths}.ts`; `src/adapters/providers/{anthropic,coding-plan-parse,filter,gemini,go,kimi,minimax,oauth,openai,registry,zai,zen}.ts`; `src/application/report-pipeline.ts`; `src/cli/{index,messages,parse-args}.ts`; `src/domain/{aggregation-defaults,aggregation,index,prediction,reset,types}.ts`; `src/i18n/translator.ts`; `src/ports/{credentials,history,http,logger,provider,renderer,translator}.ts`; `src/rendering/{colors,index,renderers,semantic-labels,status-bar}.ts`; `src/rendering/text/clip.ts`. **Modified** all current `tests/**/*.ts` (44 files, 89 source-root imports) from `src/` to `legacy/`; **committed** `legacy/`, not ignored.
- **Tasks:** `[x]` require the WU-4 explicit parallel parity receipt; `[x]` verify the tracked manifest is exactly 46 and paths are one-to-one; `[x]` move sources and retarget Vitest imports without changing assertions. Do not begin if the receipt is absent.
- **Validation:** before the move, `pnpm test` and `pnpm test:res` exit `0`; after retargeting, `pnpm test`, `pnpm test:res`, `pnpm res:build`, `pnpm build`, `node dist/cli/index.js --help`, and `bash scripts/check-secrets.sh` exit `0`; archive-integrity script exits `0` for all 46 pairs.
- **Map-to-spec:** PIPELINE-4, TEST-5, **INV-1/INV-2**, and the archive/rollback constraint. The current layout was checked: Vitest directly imports TS 89 times, so retargeting—not an inaccurate claim that Vitest still tests `src/`—is the selected collision mitigation. **Estimate:** ~46 moves plus <150 authored import edits. **Commit:** `refactor(cutover): archive TypeScript under legacy`. **Worktree:** none; `feat/rescript-cutover-archive` targets `main`.

### WU-6 — Remove Vitest and make ReScript the `pnpm test` source (depends on: WU-5)

- **Objective:** Delete the obsolete Vitest surface only after the archive and parity receipts are green, then make `pnpm test` invoke `scripts/run-tests.mjs`.
- **Files:** **Deleted** `tests/` (70 Vitest files), `vitest.config.ts`, and `tsconfig.json`; **modified** `package.json` (`test`, remove `typecheck`, `test:watch`, `test:coverage`, Vitest/coverage/TypeScript dependencies), `src/architecture/ScaffoldTests.res` (updated expectedDirs).
- **Tasks:** `[x] RED` e2e smoke harness first (E2eSmokeTests.res); `[x] GREEN` switch `test` to `node scripts/run-tests.mjs`; `[x]` remove obsolete tools in sub-slices (WU-6c.1..6); INV-1 (vitest-green) ends here.
- **Validation:** all 16 WU-6 sub-commits: ✅ pnpm test 47/47 ✅ pnpm res:build clean ✅ pnpm build clean ✅ node dist/cli/index.js --help exits 0 ✅ bash scripts/check-secrets.sh clean ✅ no vitest/typecheck/tsconfig references.
- **Map-to-spec:** TEST-1..5 final replacement, PIPELINE-3/4, **INV-1**, **INV-2**. **Commits:** 16 commits (WU-6a through WU-6c.6), all ≤400 authored lines per batch.

## Phase 5: Documentation and Final Gates

### WU-7 — Rewrite workflow documentation (depends on: WU-6)

- **Objective:** Document ReScript + rolldown as production, the codegen lifecycle, the aggregate runner, and the committed `legacy/` archive.
- **Files:** **Modified** `README.md`, `CLAUDE.md`.
- **Tasks:** `[x]` replace stale TypeScript/Vitest/typecheck commands; `[x]` document `pnpm codegen`, `pnpm res:build`, `pnpm build`, `pnpm test`, `pnpm test:res`, `pnpm postinstall`, smoke/secret gates, archive rollback, and no-CI/no-lint constraints.
- **Validation:** `pnpm test`, `pnpm build`, `node scripts/codegen.mjs --check`, `node dist/cli/index.js --help`, and `bash scripts/check-secrets.sh` exit `0`; documentation paths and commands match the final tree.
- **Map-to-spec:** PIPELINE-1..4, TEST-1..5, CODEGEN-1..6, and **INV-2** operational guidance. **Estimate:** ~200 lines. **Commit:** `docs: document ReScript production cutover`. **Worktree:** none; `docs/rescript-cutover` targets `main`.

## Chained-PR sequence

| Order | WU | PR title | Branch | Target | Estimated Δ lines |
|---:|---|---|---|---|---:|
| 1 | WU-1 | `feat(codegen): single-source-of-truth JSON via prebuild codegen` | `feat/rescript-cutover-codegen` | `main` | ~200 |
| 2 | WU-2 | `build: wire codegen into prebuild + postinstall` | `feat/rescript-cutover-codegen-wire` | `main` | ~30 |
| 3 | WU-3 | `test: aggregate ReScript test runner (parallel with vitest)` | `feat/rescript-cutover-runner` | `main` | ~150 |
| 4 | WU-4a | `test: port 6 architecture guards to ReScript` | `feat/rescript-cutover-arch-tests` | `main` | ~300 |
| 5 | WU-4b | `test: fill unit gaps + integration in ReScript` | `feat/rescript-cutover-test-gaps` | `main` | ~300 |
| 6 | WU-5 | `refactor: archive TS to legacy/ (vitest still alive)` | `feat/rescript-cutover-archive` | `main` | ~46 file moves |
| 7 | WU-6 | `build: drop vitest, switch pnpm test to ReScript runner` | `feat/rescript-cutover-drop-vitest` | `main` | ~100 + measured deletion slices |
| 8 | WU-7 | `docs: rewrite README + CLAUDE for ReScript production` | `docs/rescript-cutover` | `main` | ~200 |

For every stack position: rebase onto the latest `main` after the prior merge, keep only the current WU in the diff, and record focused command, runtime harness, rollback boundary, and result in the PR body. WU-5 and WU-6 are forbidden without the WU-4 parity-confirmed signal.

## Requirement coverage matrix

| Requirement | Satisfying WU(s) |
|---|---|
| PIPELINE-1 | WU-1, WU-2 (codegen/preres:build order) |
| PIPELINE-2 | WU-2 (three-stage order and fail-fast RED test) |
| PIPELINE-3 | WU-2, WU-6 (postinstall and fresh-install validation) |
| PIPELINE-4 | WU-2, WU-4b, WU-5, WU-6, WU-7 (CLI smoke) |
| TEST-1 | WU-3 (both suffix globs and zero-file failure) |
| TEST-2 | WU-3 (child process, timeout, signal, exit capture) |
| TEST-3 | WU-3 (aggregate non-zero on any child failure) |
| TEST-4 | WU-3 (per-file and total summary) |
| TEST-5 | WU-3, WU-4a, WU-4b, WU-5, WU-6 (parallel gate then replacement) |
| CODEGEN-1..5 | WU-1 (schema/locale generation, ignore, idempotence, round-trip/drift) |
| CODEGEN-6 | WU-1, WU-2, WU-4b (generated consumers and compile integration) |

Intentionally **NOT covered — see #3911**: the dropped Vitest coverage-threshold capability (`vitest-thresholds`) and the old `domain.parity` characterization scenario. Coverage instrumentation/bisect_ppx is out of scope; parity is established by the WU-4 receipt instead.

## Risk register

- **R-1 (parity gate failure):** If WU-4b cannot prove side-by-side parity, WU-5/WU-6 do not start. Mitigation: run both commands in parallel, record counts, and require an explicit `parity confirmed` signal.
- **R-2 (WU-5 collision):** The current Vitest tree directly imports TS 89 times. Mitigation selected from the actual layout: retarget those imports to `legacy/` in WU-5; if any cannot run, stop and ask whether to delete the affected Vitest slice rather than claim green parity.
- **R-3 (WU-4 budget):** Architecture/gap/integration additions may exceed 400 lines. Mitigation: create WU-4c before merge; no size exception is assumed.
- **R-4 (WU-6 budget):** Deleting 44 test files may exceed 400 deletions. Mitigation: WU-6a/WU-6b+ measured slices, with an orchestrator prompt for every required split.
- **R-5 (generated drift/package install):** Canonical inputs, deterministic `--check`, and a clean `pnpm install`/`postinstall` gate prevent stale generated assets; verify published-package behavior before release because development scripts are not necessarily in `files`.
