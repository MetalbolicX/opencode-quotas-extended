# Feature: %raw → typed ReScript / FFI migration

> ODD feature document. Created before the first source write (2026 session).

## Goal

Eliminate every `%raw` in the repository (production + generated + tests) and keep the
`Obj.magic` guard at zero, replacing them with typed ReScript stdlib usage and FFI externals.

## Decisions (user-approved)

1. `stringifyReason` → typed rewrite using `JsExn.anyToExnInternal` (A1) — byte-identical output.
2. Generated `Schema.res` → codegen template emits `JSON.parseOrThrow(\`…\`)` (G1); extractor + drift self-check updated.
3. Test files included (full sweep, 22 sites).
4. `%raw` architecture guard tightened to **0** after migration.

## Research evidence (pre-implementation)

- `Obj.magic`: zero occurrences repo-wide (guard-enforced, nothing to migrate).
- Production `%raw` code sites: 7 (ReportPipeline 1, ConfigLoader 5, generated Schema 1); 11/12 substring budget incl. comments.
- ReScript 12.3 stdlib `JSON` has `Boolean(bool)` + `JSON.Decode` — old "no Bool variant" comments are outdated.
- Typed enablers: `String.make: 'a => string`, `JsExn.message` (null-safe), `JsExn.anyToExnInternal`, `Nullable.isNullable`, stdlib `Promise.allSettled` (`reason: exn`), `JsError.make`.
- `coerceToPartial` runs after ajv `validateConfig` → typed JSON decoding is behavior-identical.
- `partial.aggregatedGroups` (%raw cast) is dead: `mergeConfig` re-derives groups from raw JSON.
- `settlement<'a>` in `src/bindings/Node.res` lies about `reason: 'a` — must become `reason: exn` (or stdlib allSettled).
- Equivalence trace for A1 vs raw (all input classes): wrapped JsExn, native Error, string, number, null, message-less Error, ReScript-native exn → byte-identical; 4 locked tests in `ReportPipelineReasonTests.res` pass unchanged.

## Tasks

- [x] T1. ConfigLoader.res (240b692) — remove 5 %raw casts (aggregatedGroups, show/showUnaggregated/filterByCurrentModel, progressBar); fix outdated comments.
- [x] T2. ReportPipeline.res (cd1ae2d) — typed `stringifyReason` (A1); honest `reason: exn` typing for settled reasons.
- [x] T3. codegen.mjs (6e582d0) — schema template → `JSON.parseOrThrow`; update emitter, extractor, drift self-check; regenerate Schema.res.
- [x] T4. Tests (f0b50fa) — migrate 22 %raw sites (JsError.make, processEnv Dict ops, chdir FFI in Node.res, String.make).
- [x] T5. TypeSafetyGuardsTests (e96a9a8) — tighten %raw budget to 0; reword %raw-mentioning comments.
- [x] T6. All five gates green; close out.

## Evidence log

| Commit | Scope |
|---|---|
| 240b692 | refactor(infra): ConfigLoader typed JSON decoding, dead field removed |
| cd1ae2d | refactor(application): typed stringifyReason + settlement.reason: exn |
| 6e582d0 | refactor(scripts): codegen emits JSON.parseOrThrow schema |
| f0b50fa | refactor(tests): 22 %raw sites → typed stdlib/FFI |
| e96a9a8 | fix(architecture): guards actually count (Js.String.split arg order); %raw budget → 0 |

### Pre-existing bug found during verification

`countSubstring` called `Js.String.split(src, pat)`, but ReScript 12 signs it
`(separator, string)` — both architecture guards always counted 0 (vacuous).
Fixed in e96a9a8 and proven with probe files: each guard now fails on a
violating file and passes on a clean tree.

### Final state

- `%raw` in src/: 8 mentions, all inside the guard test's own strings (excluded from its walk)
- `%raw` in scripts/: 0; `Obj.magic` in src (non-test): 0
- All five gates green (codegen --check, 55 test files, pnpm build, smoke, secrets)
