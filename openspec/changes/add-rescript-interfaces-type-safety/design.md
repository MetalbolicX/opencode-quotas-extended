# Design: Add ReScript Interfaces & Type Safety

## Technical Approach

Implement the refactor in six TDD phases (P1–P6). Each phase writes RED contract/behavior tests first, then restores GREEN with the ReScript compiler (`rescript build`) as the type gate and `pnpm test` plus the rescript-test scripts as the behavior gate. Provider output is normalized to the domain `quotaData` shape at the adapter boundary; typed JSON values are decoded before entering config/history state.

```text
createXProvider() → Provider.quotaProvider → Registry → ReportPipeline/Cli → Renderers
JSON.parse → JSON.t pattern matchers → ConfigLoader/JsonFileHistory → typed state
```

## Architecture Decisions

### Decision: Provider type unification
**Choice**: All eight `createXProvider()` functions return `Provider.quotaProvider` from `src/ports/Provider.resi`; Registry stores that type directly.
**Alternatives considered**: Keep nominal per-module types plus `Obj.magic` (rejected: unsound and the root cause of the 14 provider-boundary casts).
**Rationale**: One port contract removes `private_coerce`/`sharedProvider`, lets CLI and renderers consume providers directly, and forces provider records to use the domain `Date.t`/window representation.

### Decision: Test factory extraction
**Choice**: Move `makeQuotaData`, `makeHistoryPoint`, `makeQuotaSnapshot`, and `makeAggregationGroup` to `src/testing/DomainFixtures.res`.
**Alternatives considered**: Keep factories in domain modules and hide them through `.resi` (rejected: test concerns remain in the pure domain surface).
**Rationale**: Production domain interfaces expose only domain behavior; tests import fixtures explicitly.

### Decision: Manual JSON decoders
**Choice**: Use private `JSON.t` pattern-matching helpers in ConfigLoader and JsonFileHistory, with a shared helper only if duplication is proven.
**Alternatives considered**: Add `rescript-json` (rejected by user; unnecessary dependency).
**Rationale**: Explicit decoding preserves current defaults/deprecation behavior without unchecked JavaScript field access.

### Decision: Node FFI externals
**Choice**: Replace the four bottom-of-`Node.res` `%raw` helpers with typed `@val`/`@scope("process")` externals.
**Alternatives considered**: Retain inline `%raw` wrappers (rejected: compiler cannot validate signatures).
**Rationale**: Node APIs become auditable contracts while generated JavaScript behavior remains unchanged.

### Decision: `.resi` policy
**Choice**: Add interfaces only to modules consumed across module boundaries; keep internal helpers private.
**Alternatives considered**: Add `.resi` to every `.res` file (rejected: maintenance noise and accidental API expansion).
**Rationale**: Interfaces document intentional public surfaces and make drift compiler-visible.

## Data Flow

Factories and provider parsers produce `Domain.quotaData`; `Registry.all/get` expose `Provider.quotaProvider`; `ReportPipeline`, CLI filters, and renderers share that exact type. Config/history adapters parse `JSON.t` into typed records and retain existing validation, defaults, reset handling, and persistence semantics.

## File Changes

| File | Action | Description |
|---|---|---|
| `src/testing/DomainFixtures.res` | Create | Test-only domain factories. |
| `src/domain/Types.res` | Modify | Remove factories; retain production types/helpers. |
| `src/domain/Aggregation.res` | Modify | Remove `makeAggregationGroup`. |
| `src/domain/Domain.res` | Modify | Drop factory re-exports. |
| `src/domain/{Types,Aggregation,Prediction,Reset,AggregationDefaults}.resi`, `src/testing/DomainFixtures.resi` | Create | P1 public contracts. |
| `src/Providers/{QuotaData,CodingPlanParse}.res` | Modify | Alias/produce `Domain` types instead of duplicate provider records. |
| `src/Providers/Registry.res` | Modify | Delete `private_coerce`/`sharedProvider`; use the port type. |
| `src/Providers/{OpenAI,Zen,Go,Zai,Kimi,Minimax,Anthropic,Gemini}.res` | Modify | Return `Provider.quotaProvider`; normalize records. |
| `src/application/ReportPipeline.res`, `src/Providers/Filter.res` | Modify | Consume the shared provider contract. |
| `src/Providers/*.resi` (8) and `src/Providers/Registry.resi` | Create | Export typed creators and registry API. |
| `src/rendering/Renderers.res`, `src/Cli/Cli.res`, `src/Cli/ParseArgs.res` | Modify | Remove `Obj.magic`; type renderer/provider and parse options. |
| `src/Infra/ConfigLoader.res`, `src/Infra/JsonFileHistory.res` | Modify | Add manual JSON decoders. |
| `src/bindings/Node.res` | Modify | Replace four `%raw` bindings with externals. |
| `src/Infra/{FetchHttp,JsonFileHistory,Paths,ConfigLoader}.resi`, `src/rendering/{Renderers,Colors}.resi`, `src/i18n/{Translator,Messages}.resi`, `src/Cli/{Cli,ParseArgs}.resi`, `src/bindings/Node.resi` | Create | Cross-module interfaces. |
| `src/{domain/Domain,Providers/Providers,Auth/Auth,Infra/Infra}.resi` | Create | Four barrel contracts. |

## Interfaces / Contracts

From `Provider.resi`:

```rescript
open Domain

type quotaProvider = {
  id: string, displayName: string, category: string,
  authStrategy: authStrategy,
  isAvailable: unit => promise<bool>,
  fetchQuotas: unit => promise<array<quotaData>>,
}
```

Representative interfaces:

```rescript
// Types.resi
type quotaData = { id: string, providerName: string, used: float, limit: option<float>, unit: string, reset: option<Date.t>, window: windowType, info: option<string>, modelId: option<string> }
let windowToString: windowType => string
let windowFromString: string => option<windowType>

// Registry.resi
type providerRegistry = { ids: unit => array<string>, get: string => option<Provider.quotaProvider>, all: unit => array<Provider.quotaProvider> }
let allProviders: unit => array<Provider.quotaProvider>
```

Decoder contracts (private unless shared): `optionalString: JSON.t => option<string>`, `optionalFloat: JSON.t => option<float>`, `optionalBool: JSON.t => option<bool>`, `optionalObject: JSON.t => option<dict<JSON.t>>`, and `decodeDict: (JSON.t, JSON.t => option<'a>) => dict<'a>`.

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Unit | New `.resi` surfaces, fixture extraction, provider normalization, decoders, and Node bindings | RED first; compile with `rescript build`, then run affected rescript-test scripts. |
| Integration | Public-boundary and unsafe-pattern invariants | Add one `tests/architecture/` test for required `.resi` files and one for `%raw`/`Obj.magic` reductions; keep all 641 Vitest tests green. |

## Threat Matrix

N/A — no routing, shell, subprocess, VCS/PR automation, executable-file classification, or process-integration boundary.

## Migration / Rollout

No migration required. P1–P6 use separate, revertible git commits with per-phase RED/GREEN verification.

## Open Questions

None — all technical decisions are locked by the user.
