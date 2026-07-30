# Proposal: Add ReScript Interfaces & Type Safety

## Intent

Add ReScript interface (`.resi`) files to enforce public API boundaries and eliminate 84 unsafe escape hatches (58 `%raw` + 26 `Obj.magic`) by replacing them with typed constructs. Only 6 of 79 modules currently have `.resi` files (all in `src/ports/`); nominal-record-typing across 8 providers plus untyped JSON parsing force pervasive unsafe coercion through Registry → Renderers → Cli.

## Scope

### In Scope
- **P1**: Extract domain test factories → `src/testing/DomainFixtures.res`; `.resi` for Types, Aggregation, Prediction, Reset, AggregationDefaults, DomainFixtures.
- **P2**: Unify 8 provider creators → `Provider.quotaProvider`; delete `Registry.private_coerce`/`sharedProvider`; remove 14 boundary `Obj.magic` (Renderers 9 + Cli 4 + ParseArgs 1); `.resi` for Registry + providers.
- **P3**: Manual JSON decoders in ConfigLoader + JsonFileHistory; remove 16 `%raw` + 4 `Obj.magic`.
- **P4**: Convert `Node.res` 4 `%raw` → `@val`/`@scope` externals.
- **P5**: `.resi` for Auth, Cli, ParseArgs, Renderers, Colors, Translator, Messages, FetchHttp, Paths, ConfigLoader.
- **P6**: Barrel `.resi` (Domain, Providers, Auth, Infra).

### Out of Scope
- CI workflow; eslint/biome; test-only `%raw` env hacks (defer to a TestHelpers module later); ETTL history wiring.

## Capabilities

### New Capabilities
None — refactor of existing ReScript modules; no capabilities exist under `openspec/specs/`.

### Modified Capabilities
None.

## Approach

Phased, each phase TDD-driven (red→green→refactor) per locked decision #6. ReScript compiler (`rescript build`) is the primary type gate; `pnpm test` (641 vitest) + ReScript test scripts are the behavior gate. No third-party JSON deps (#3) — manual decoders; `.resi` only for modules consumed across boundaries (#4).

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `src/domain/*` | Modified | `.resi` files; test-factory extraction |
| `src/testing/*` | New | `DomainFixtures.res` (+ `.resi`) |
| `src/ports/*` | Modified | `Provider.quotaProvider` becomes unified return type |
| `src/Providers/*` | Modified | 8 creators return `Provider.quotaProvider`; Registry `.resi` |
| `src/rendering/*` | Modified | Remove `Obj.magic`; `.resi` |
| `src/Cli/*` | Modified | Remove `Obj.magic`; `.resi` for Cli, ParseArgs |
| `src/Infra/*` | Modified | JSON decoders; `.resi` for ConfigLoader, FetchHttp, Paths |
| `src/Auth/*` | Modified | `.resi` |
| `src/bindings/*` | Modified | `Node.res` `@val`/`@scope` externals |
| `src/application/*` | Modified | Barrel `.resi` (Domain, Providers, Auth, Infra) |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Test breakage from helper move | Medium | Atomic import update across ~20 test files; full suite run |
| `.resi` drift | Medium | Architecture test enforces `.resi` for cross-module consumers |
| Provider refactor touches 8 modules | High | Per-module TDD; `rescript build` after each |
| ReScript compiler is sole type gate | Low | Intended mechanism — `.resi` IS the type boundary |

## Rollback Plan

Each phase is a separate git commit; revert per-phase. Provider unification is reversible — creators only change return type, logic unchanged.

## Dependencies

None.

## Success Criteria

- [ ] `rescript build` clean (zero warnings-as-errors regression).
- [ ] `pnpm test` — 641+ tests green.
- [ ] `%raw` in `src/` (excl. `*Tests.res`) reduced by ≥70%.
- [ ] `Obj.magic` in `src/` reduced by ≥80%.
- [ ] Every cross-module-consumer module has a `.resi`.
