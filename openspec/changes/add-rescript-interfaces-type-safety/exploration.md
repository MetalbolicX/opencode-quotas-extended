# Exploration: add-rescript-interfaces-type-safety

## Current State

The codebase has 79 `.res` files and only 6 `.resi` interface files — all confined to `src/ports/` (Provider, Credentials, Http, Renderer, Logger, History). Every other module is `.res` only, meaning the public surface area is largely untyped from the outside.

Two unsafe patterns pervade the codebase:

1. **Nominal → structural coercion via `Obj.magic`**: Each of the 8 provider modules (`OpenAI`, `Zen`, `Go`, `Zai`, `Kimi`, `Minimax`, `Anthropic`, `Gemini`) defines its own local `quotaProvider` record type (structurally identical but nominally distinct). `Registry.res:32` uses `let private_coerce: 'a => sharedProvider = %raw("(v) => v")` + `Obj.magic` to slam them into a homogeneous array. This leaks into `Renderers.res` (9 `Obj.magic` usages) and `Cli.res` (4 `Obj.magic` usages), where providers flow through the renderer boundary and CLI get/list operations.

2. **Untyped JSON field extraction**: `ConfigLoader.res:210–226` has 12 consecutive `%raw` lines in `coerceToPartial` doing unchecked JS field access with `=== undefined` guards. `aggregatedGroups` parsing (lines 329–351) chains 4 `Obj.magic` calls to convert `groups[key]["strategy"]` and `groups[key]["members"]` from untyped JS objects. `JsonFileHistory.res` uses 4 more `%raw` calls for JS object → dict conversion.

**Counts confirmed from source:**
- 58 `%raw` usages across `.res` files
- 26 `Obj.magic` usages across `.res` files
- 6 `.resi` files (all ports, all interface-only with no corresponding `.res`)
- `rescript.json` warning flags: `"error": "+101+102+5+7"` (raw JS + Obj.magic + unused + fragment)

**Architecture:** Pure hexagonal layout — `src/domain/` (zero I/O), `src/ports/` (interfaces), `src/Providers/`, `src/Auth/`, `src/Infra/`, `src/rendering/`, `src/Cli/`, `src/application/` — with barrel files `Domain.res`, `Providers.res`, `Auth.res`, `Infra.res` re-exporting key types.

---

## Affected Areas

| File | Role | Why Affected |
|------|------|--------------|
| `src/ports/Provider.resi` | Shared quotaProvider port type | Target type for provider unification |
| `src/Providers/Registry.res` | Registry — `private_coerce`, `sharedProvider`, `allProviders` | Core of Cluster 1; must be refactored |
| `src/Providers/*.res` (8 files) | Individual provider creators | Each has a nominal local `quotaProvider` type |
| `src/rendering/Renderers.res` | 9 `Obj.magic` usages | Receives coerced providers; needs typed boundary |
| `src/Cli/Cli.res` | 4 `Obj.magic` usages | CLI get/list operations on registry |
| `src/Cli/ParseArgs.res` | 5 `Obj.magic` usages | Arg parse untyped extraction |
| `src/Infra/ConfigLoader.res` | 12 `%raw` in `coerceToPartial` + 4 `Obj.magic` chain for `aggregatedGroups` | Core of Cluster 2 |
| `src/Infra/JsonFileHistory.res` | 4 `%raw` for JS dict conversion | Cluster 2 JSON untyped access |
| `src/domain/Types.res:116–154` | Test helpers (`makeQuotaData`, `makeHistoryPoint`, `makeQuotaSnapshot`, `makeAggregationGroup`) | Candidate for extraction to `src/testing/DomainFixtures.res` |
| `Domain.res`, `Providers.res`, `Auth.res`, `Infra.res` | Barrel re-export files | Need `.resi` counterparts |
| `rescript.json` | Compiler config | Warning flags for unsafe constructs |

---

## Approaches

### Phased plan (recommended — user-decided)

**P1 — Domain interfaces + test fixtures**
- Create `.resi` files for all `src/domain/*.res` modules that expose types/functions used elsewhere
- Extract test helpers from `Types.res` into `src/testing/DomainFixtures.res` (makes `.resi` clean of test-only concerns)
- Add `.resi` for `DomainFixtures.res`

**P2 — Provider type unification**
- Make all 8 provider creators return `Provider.quotaProvider` (the port type from `src/ports/Provider.resi`) directly — eliminating the nominal types and `Registry.res`'s `private_coerce`/`Obj.magic`
- Remove `Registry.res`'s local `sharedProvider` type and `private_coerce`
- Remove `Renderers.res` and `Cli.res` `Obj.magic` usages at the provider boundary

**P3 — Typed JSON decoders for ConfigLoader**
- Replace the 12 `%raw` lines in `coerceToPartial` with manual ReScript JSON decoders (`Json.Decode.object`, `Json.Decode.array`, `Json.Decode.string`, `Json.Decode.bool`, `Json.Decode.float`, `optional` combinators)
- Replace the 4-call `Obj.magic` chain in `aggregatedGroups` with a proper `aggregationGroup` decoder
- Eliminate `%raw` from `JsonFileHistory.res` dict conversion using `Js.Dict` bindings

**P4 — Node FFI cleanup**
- Audit remaining `%raw` in `Node.res`, `Paths.res`, `FetchHttp.res` for typed replacements (many are benign Node built-ins like `process.cwd()`, `import.meta.url` — flag only where unsafety is real)

**P5 — Auth, Cli, rendering `.resi` files**
- Add `.resi` for `Auth.res`, `Cli.res`, `ParseArgs.res`, `Renderers.res`, `JsonFileHistory.res`, `CredentialResolver.res`, `ConfigLoader.res`

**P6 — Barrel `.resi` files**
- Create `Domain.resi`, `Providers.resi`, `Auth.resi`, `Infra.resi` exposing public API surfaces

### Alternatives rejected

- **Keep `Obj.magic`**: Accepted technical debt — type soundness violation; cascades through the call chain
- **Add `rescript-json` dependency**: Adds a third-party dep with its own compatibility surface; manual decoders are verbose but zero-dependency and explicit

---

## Recommendation

Adopt the **phased plan** above. The work is partitioned so each phase is independently verifiable and touches a manageable blast radius:

- P1: Safe — pure domain types and test fixture extraction
- P2: High-value — removes the core `Obj.magic` from the hottest path (provider registry → renderer/CLI)
- P3: High-value — eliminates the largest cluster of unsafe JSON access
- P4–P6: Lower urgency — polish and completeness

---

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Test breakage from helper move** | Medium | `Types.res` helpers are used in ~20 test files; all imports must be updated atomically; run full test suite after move |
| **`.resi` drift** | Medium | `.resi` must be kept in sync manually; add architecture test to enforce `.resi` existence for every module used across module boundaries |
| **Provider refactor touches 8 modules** | High | Each provider's creator must be audited for return type; P2 is all-or-nothing per provider; incremental validation with `pnpm typecheck` after each provider |
| **Manual decoder verbosity** | Low | Verbose but correct; consider a small `Json.optional` / `Json.field` helper module to reduce boilerplate |
| **ReScript compiler is sole type gate** | Low | No runtime type safety beyond what the compiler enforces; no TypeScript-style declaration files — the `.resi` approach is the intended mechanism |

---

## Ready for Proposal

**Yes.**

The change is well-scoped, the root causes are verified against source, and a concrete phased plan exists. The orchestrator should proceed to `sdd-propose` with the P1–P6 breakdown, capturing the user decisions (manual decoders, provider unification to `Provider.quotaProvider`, `DomainFixtures.res` extraction, barrel `.resi` files).
