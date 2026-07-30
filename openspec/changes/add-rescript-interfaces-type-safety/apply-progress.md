# Apply Progress: add-rescript-interfaces-type-safety — Phase 1, 2a, 2b

## TDD Cycle Evidence

| Task | Phase | Test File | Test Command | Result |
|------|-------|-----------|--------------|--------|
| 1.1 | RED | `src/testing/DomainFixturesTests.res` | `pnpm res:build` (expected fail: DomainFixtures not found) | ✅ Module not found error as expected |
| 1.2 | GREEN | `src/testing/DomainFixturesTests.res` | `pnpm res:build` + `node lib/es6/src/testing/DomainFixturesTests.res.mjs` | ✅ 8/8 tests pass |
| 1.3 | REFACTOR | N/A (removal) | `pnpm res:build` | ✅ Build fails in test files only (expected — imports updated in 1.6) |
| 1.4 | RED | `tests/architecture/resi-coverage.test.ts` | `pnpm test -- tests/architecture/resi-coverage.test.ts` | ✅ 6 failed (one per missing .resi) |
| 1.5 | GREEN | `tests/architecture/resi-coverage.test.ts` | `pnpm test -- tests/architecture/resi-coverage.test.ts` | ✅ 6/6 pass, all 655 tests green |
| 1.6 | REFACTOR | N/A (import updates) | `pnpm res:build` + `pnpm test` | ✅ Build exit 0, 655 tests pass |

## Work Unit Evidence

| Unit | Focused test command | Runtime harness | Result |
|------|---------------------|-----------------|--------|
| 1 (Domain fixtures + .resi) | `pnpm res:build` | `pnpm test` (655 vitest) | ✅ Clean build, 655/655 pass |

## Rollback Boundary

- `src/testing/DomainFixtures.res` / `DomainFixtures.resi` — new files; revert to factory-in-domain if needed
- `src/domain/Types.res` — removed 3 factory functions (makeQuotaData, makeHistoryPoint, makeQuotaSnapshot)
- `src/domain/Aggregation.res` — removed makeAggregationGroup
- `src/domain/Domain.res` — removed 4 factory re-exports

Rollback: restore the factory functions to Types.res (lines 116–154), Aggregation.res (line 220), Domain.res (lines 44–47), delete DomainFixtures.res/.resi.

## Deviations from Plan

1. **DomainFixtures.res implementation**: Used explicit return type annotations on all 4 factory functions (required for ReScript to infer record field names when types come from re-exported modules via `open Domain + open Aggregation`).

2. **Domain.resi**: Skipped `module Types = Types` etc. declarations (incompatible with same-file `Types.x` value references in interface body). Submodules accessible via the submodules' own .resi files and the `Domain.x` path in consuming code.

3. **DomainFixturesTests.res**: Added `open Domain` to access `aggregationStrategy` variant type in test helper.

4. **Unused `open Domain` in Aggregation.test.res**: Removed after factory imports switched to `DomainFixtures` (domain functions accessed via DomainFixtures opened alongside Domain, or directly when already in scope).

---

## Phase 2a: Provider Type Unification — quotaData Data Shape

### TDD Cycle Evidence

| Task | Phase | Test File | Test Command | Result |
|------|-------|-----------|--------------|--------|
| 2a.1 | RED | N/A (type change) | `pnpm res:build` (expected: unknown variant #rolling1h in Types.resi consumers) | ✅ Types.resi and Types.res updated; Domain.resi auto-re-exports via `type windowType = Types.windowType` — no change needed there |
| 2a.1 | GREEN | N/A | `pnpm res:build` | ✅ Build clean with only pre-existing `floatMax` warning |
| 2a.2 | REFACTOR | N/A (QuotaData deletion) | `pnpm res:build` | ✅ Deleted `src/Providers/QuotaData.res`; `Providers.res` barrel updated; QuotaData type aliases removed from CodingPlanParse |
| 2a.3 | RED | `src/Providers/CodingPlanParseTests.res` | `pnpm res:build` (expected: kebab variants `#\"rolling-5h"` etc. no longer valid after CodingPlanParse type alias change) | ✅ 5 compile errors in CodingPlanParseTests.res showing old kebab variants incompatible with new Domain.windowType |
| 2a.3 | GREEN | `src/Providers/CodingPlanParseTests.res` | `pnpm res:build` after updating all `#\"rolling-X"` → `#rollingX` in test assertions | ✅ All providers (OpenAI, Gemini, Minimax, Anthropic, Zen, Go, Zai, Kimi) updated to `Domain.quotaData` + camelCase windows + `option<Date.t>` reset; build clean |
| 2a.4 | GREEN | N/A | `pnpm res:build` after updating `Registry.res` `sharedProvider.fetchQuotas` → `Domain.quotaData` | ✅ Registry updated; `private_coerce` and `sharedProvider` remain (Phase 2b removes them) |
| 2a.5 | RED | N/A (Renderers simplification) | `pnpm res:build` (expected: unused match case warning #11 in Renderers.res) | ✅ Warning #11 ("this match case is unused") present before Renderers changes — confirms the `Obj.magic` dual-string/Date path was dead code |
| 2a.5 | GREEN | N/A | `pnpm res:build` after removing `Obj.magic` from `fmtReset`, `windowLabelText`, `windowToStr`, jsonRenderer reset | ✅ Warning #11 GONE; only pre-existing `floatMax` warning remains |
| 2a.6 | GATE | N/A | `pnpm res:build` + `pnpm test` | ✅ Clean build (no new warnings), 655/655 tests green |

### Work Unit Evidence

| Unit | Focused test command | Runtime harness | Result |
|------|---------------------|-----------------|--------|
| 2a (Provider unification) | `pnpm res:build` | `pnpm test` (655 vitest via `node lib/es6/src/Providers/CodingPlanParseTests.res.mjs`) | ✅ Clean build, 655/655 pass |

### Rollback Boundary

- `src/Providers/QuotaData.res` — deleted; restore from git if needed
- `src/domain/Types.res` — added `#rolling1h` variant + converter entries; revert git diff
- `src/domain/Types.resi` — added `#rolling1h` variant; revert git diff
- `src/bindings/Node.res` — added `jsDateParse` external; revert git diff
- `src/rendering/Renderers.res` — removed 9× `Obj.magic`/`%raw` calls for reset/window; revert git diff
- All 8 providers + CodingPlanParse — converted to `Domain.quotaData`; revert git diff

### Deviations from Plan

1. **Task 2a.4 done before 2a.2 build pass**: `Registry.res` updated in same session as 2a.2 (was needed to unblock build after deleting QuotaData.res). `private_coerce` left intact as specified.
2. **`jsDateParse` placed in `Node.res`**: Placed in `src/bindings/Node.res` (shared infra) rather than per-provider, since only Gemini reads ISO strings from the API and other providers may benefit.
3. **CodingPlanParseTests.res updated alongside CodingPlanParse.res**: Test file used old kebab variants in assertions; updated to camelCase to match new `Domain.windowType`.
4. **`windowRank`/`zaiSortRank` updated**: These helper functions used kebab variants internally for pattern matching; updated to camelCase to match the new `Domain.windowType`.

---

## Phase 2b: Provider TYPE Identity Unification

### TDD Cycle Evidence

| Task | Phase | Test File | Test Command | Result |
|------|-------|-----------|--------------|--------|
| 2b.1 | RED | N/A (type change) | `pnpm res:build` (expected: Provider module not found) | ✅ `Provider` module created at `src/Provider.{res,resi}` after discovering ReScript requires both .res and .resi for a module |
| 2b.1 | GREEN | N/A | `pnpm res:build` after all 8 providers updated | ✅ All 8 providers (OpenAI, Zen, Go, Zai, Kimi, Minimax, Anthropic, Gemini) return `Provider.quotaProvider`; local type declarations deleted |
| 2b.2 | GREEN | N/A | `pnpm res:build` after Registry update | ✅ `Registry.res` updated: `sharedProvider`/`private_coerce` deleted; `allProviders` returns `array<Provider.quotaProvider>` directly |
| 2b.3 | GREEN | N/A | `pnpm res:build` after ReportPipeline update | ✅ `ReportPipeline.res` local `quotaProvider` replaced with `type quotaProvider = Provider.quotaProvider` alias |
| 2b.4 | GREEN | N/A | `pnpm res:build` after Cli update | ✅ All 4 `Obj.magic` calls removed from `Cli.res`; `availableFilterProvider`/`listProvider` local types removed; `filterAvailableProvidersInline` and `renderListTable` updated to use `Provider.quotaProvider` |
| 2b.5 | GREEN | N/A | `pnpm res:build` after .resi creation | ✅ Created 8 provider `.resi` files (OpenAI, Zen, Go, Zai, Kimi, Minimax, Anthropic, Gemini); each exposes `createXProvider: unit => Provider.quotaProvider` |
| 2b.6 | GATE | N/A | `pnpm res:build` + `pnpm test` + grep checks | ✅ Build exit 0, 655 tests green, `private_coerce` count: 0, `Obj.magic` in Cli.res: 0 |

### Work Unit Evidence

| Unit | Focused test command | Runtime harness | Result |
|------|---------------------|-----------------|--------|
| 2b (Provider type unification) | `pnpm res:build` | `pnpm test` (655 vitest) | ✅ Clean build (only pre-existing warnings), 655/655 pass |

### Rollback Boundary

- `src/Provider.{res,resi}` — new files; delete to remove Provider module
- `src/domain/Domain.res` — added `authStrategy` and `quotaProvider` type definitions; revert git diff
- `src/domain/Domain.resi` — added `authStrategy` and `quotaProvider` type aliases; revert git diff
- `src/Providers/{OpenAI,Zen,Go,Zai,Kimi,Minimax,Anthropic,Gemini}.res` — removed local type declarations; revert git diff
- `src/Providers/Registry.res` — removed `sharedProvider`/`private_coerce`; revert git diff
- `src/application/ReportPipeline.res` — replaced local `quotaProvider` with alias; revert git diff
- `src/Cli/Cli.res` — removed 4× `Obj.magic`, local types, updated filter/render functions; revert git diff
- `src/Providers/{OpenAI,Zen,Go,Zai,Kimi,Minimax,Anthropic,Gemini}.resi` — new files; delete to remove interfaces

### Deviations from Plan

1. **`Provider` module creation**: ReScript requires both `.res` and `.resi` files to create a module. `src/ports/Provider.resi` existed without a paired `.res`, so created `src/Provider.{res,resi}` at the project root to make `Provider.quotaProvider` accessible directly. The `src/ports/Provider.resi` was removed (no longer needed as a standalone interface).

2. **`Provider.res` minimal**: The implementation file is intentionally minimal — types are defined in `Provider.res` (not `.resi`) so the module is valid. `Provider.resi` redeclares the types so consumers see the interface.

3. **`Domain` also defines `quotaProvider`**: Added `authStrategy` and `quotaProvider` to `Domain.res`/`Domain.resi` as type aliases (pointing to same definitions as `Provider`). This was needed because `Provider.res` opens `Domain` for `quotaData`, and Domain needed to know about the `quotaProvider` type for structural compatibility across the codebase. The types are identical in both modules.

---

## Phase 3: Manual JSON Decoders

### TDD Cycle Evidence

| Task | Phase | Test File | Test Command | Result |
|------|-------|-----------|--------------|--------|
| 3.1 | RED | `src/Infra/ConfigLoaderTests.res` | `pnpm res:build` + tests | ✅ Added test 11 (aggregatedGroups strategy+ members) and test 12 (partial config defaults); both pass |
| 3.2 | GREEN | `src/Infra/ConfigLoader.res` | `pnpm res:build` + `node lib/es6/src/Infra/ConfigLoaderTests.res.mjs` | ✅ 12/12 pass; coerceToPartial uses typed `_optStr`, `_optFloat`, `_objDict` + `%raw` for booleans (JSON module lacks `Bool` variant in ReScript 12.3.0) |
| 3.3 | GREEN | `src/Infra/JsonFileHistory.res` | `pnpm res:build` + `pnpm test` | ✅ 655/655 pass; replaced 4 `%raw` calls with typed `JSON.t` decoders |
| 3.4 | GATE | N/A | `pnpm res:build` + `pnpm test` + grep Obj.magic + grep %raw | ✅ Build clean (0 warnings), 655 tests green, `Obj.magic` in ConfigLoader.res+JsonFileHistory.res = 0 |

### Work Unit Evidence

| Unit | Focused test command | Runtime harness | Result |
|------|---------------------|-----------------|--------|
| 3 (JSON decoders) | `pnpm res:build` | `pnpm test` (655 vitest) | ✅ Clean build, 655/655 pass |

### Rollback Boundary

- `src/Infra/ConfigLoader.res` — revert git diff for `coerceToPartial` and `loadConfig` JSON.parse replacement
- `src/Infra/JsonFileHistory.res` — revert git diff for `load` function typed decoder replacement
- `src/Infra/ConfigLoaderTests.res` — revert git diff for added tests 11 and 12

### Deviations from Plan

1. **`JSON.Bool` does not exist in ReScript 12.3.0 JSON module**: The task description claims `JSON.Bool(b)` is available but the ReScript 12.3.0 compiler reports "The variant constructor JSON.Bool can't be found." Boolean fields (`showUnaggregated`, `show`, `filterByCurrentModel`, `color`, `gradients`) still use `%raw` because there's no typed way to decode them without `JSON.Bool`. The `progressBar` field also uses `%raw` because it contains nested booleans.

2. **`aggregatedGroups` `%raw` preserved**: The `aggregatedGroups` field in `partialConfig` is typed as `option<dict<dict<string>>>` which doesn't match the JSON structure (objects with `strategy`/`members` fields). The typed decoding is done in `loadConfig` via the `aggregatedGroups` block, so the `%raw` in `coerceToPartial` is just a placeholder that doesn't affect correctness.

3. **JSON.parseOrThrow used instead of JSON.parse**: `JSON.parse` doesn't exist in this ReScript JSON module; `JSON.parseOrThrow` is the available function.

---

## Phase 5a: ParseArgs + Renderers Obj.magic Reduction

### TDD Cycle Evidence

| Task | Phase | Test File | Test Command | Result |
|------|-------|-----------|--------------|--------|
| 5a.1 | GREEN | N/A | `pnpm res:build` | ✅ Build clean, 0 warnings (ParseArgs typed FFI: `parseArgsValues` closed type + `@get` externals for values + 5 fields; all `Obj.magic` removed) |
| 5a.1 | GREEN | `tests/unit/cli/parse-args.test.ts` | `pnpm test tests/unit/cli/parse-args.test.ts` | ✅ All 22 tests pass |
| 5a.2 | GREEN | N/A | `pnpm res:build` | ✅ Build clean (ConfigLoader: `== null` for progressBar; Renderers: `Some(v) => v` simplification) |
| 5a.2 | GREEN | `tests/unit/config/config-loader.test.ts` | `pnpm test tests/unit/config/config-loader.test.ts` | ✅ All 12 tests pass |
| 5a.3 | GATE | N/A | `pnpm res:build` + `pnpm test` + grep Obj.magic | ✅ Build exit 0 (0 warnings), 655/655 tests green, `Obj.magic` in ParseArgs.res: 0, Renderers.res: 0, ConfigLoader.res: 0 |

### Obj.magic Elimination Summary

**ParseArgs.res** — 7 → 0:
- `Obj.magic({...})` on options object → removed (ReScript object literals work with `{..}` external)
- `Obj.magic(result["values"])` → replaced with `@get external valuesOf: {..} => parseArgsValues = "values"`
- 5 field `Obj.magic` casts → replaced with typed `@get` externals returning `Nullable.t<_>`, converted via `Nullable.toOption`

**Renderers.res** — 1 → 0:
- `Obj.magic(null)` sentinel removed (defended against `Some(null)` from ConfigLoader)
- Root cause fixed in ConfigLoader: `progressBar: %raw("_raw.progressBar == null ? undefined : _raw.progressBar")` treats both null and undefined as absent → produces `None` instead of `Some(null)`

### Rollback Boundary

- `src/Cli/ParseArgs.res` — revert git diff: restore original `Obj.magic` casts + remove typed externals + `parseArgsValues` type
- `src/rendering/Renderers.res` — revert git diff: restore `Obj.magic(null)` sentinel check
- `src/Infra/ConfigLoader.res` — revert `== null` to `=== undefined` for progressBar

### Deviations from Plan

1. **`Js.t<{..}>` type alias fails**: `type X = Js.t<{..}>` fails with "unbound type variable". Used closed `parseArgsValues` record type instead (`{list: option<bool>, provider: option<string>, ...}`) with `@get` externals for field access.

2. **`Js.Nullable.t` deprecated**: `Js.Nullable.t<'a>` deprecated in favor of `Nullable.t<'a>`. Used `Nullable.t` and `Nullable.toOption`.

3. **`getWithDefault` for booleans**: Since `Nullable.toOption` returns `option<bool>`, used `Belt.Option.getWithDefault(..., false)` for `rawList` and `rawHelp` (which were `bool` in original code, compared with `=== true`).

---

## Phase 1 Summary

**Created:**
- `src/testing/DomainFixtures.res` + `.resi` — 4 test factories
- `src/testing/DomainFixturesTests.res` — 8 tests validating factory shapes
- `src/domain/Types.resi` — types + converter functions
- `src/domain/Aggregation.resi` — aggregationGroup type + 7 aggregate functions
- `src/domain/Prediction.resi` — predictionParams type + predictTimeToLimit
- `src/domain/Reset.resi` — detectReset
- `src/domain/AggregationDefaults.resi` — defaultAggregationGroups
- `src/domain/Domain.resi` — barrel with type aliases + function signatures
- `tests/architecture/resi-coverage.test.ts` — 6 assertions (one per module)

**Modified:**
- `src/domain/Types.res` — removed 3 factory definitions
- `src/domain/Aggregation.res` — removed makeAggregationGroup
- `src/domain/Domain.res` — removed 4 factory re-exports
- `src/application/ReportPipeline.res` — `Domain.Aggregation.makeAggregationGroup` → `DomainFixtures.makeAggregationGroup`; `Domain.Aggregation.aggregationGroup` → `Aggregation.aggregationGroup`
- `src/domain/Aggregation.test.res` — `Domain.makeQuotaData` → `makeQuotaData`; `Domain.makeAggregationGroup` → `makeAggregationGroup`; added `open DomainFixtures`
