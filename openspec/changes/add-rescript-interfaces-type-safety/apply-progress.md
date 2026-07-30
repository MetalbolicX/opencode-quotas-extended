# Apply Progress: add-rescript-interfaces-type-safety — Phase 1

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
