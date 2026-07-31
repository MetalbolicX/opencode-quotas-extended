# Asset Codegen Specification

## Purpose

Establish a single source of truth for the two duplicated JSON assets — `schemas/quotas.schema.json` and `src/i18n/locales/en.json` — by generating the `.res` modules that currently inline them via `%raw` and `Dict.fromArray`. A `scripts/codegen.mjs` reads the canonical JSON and emits git-ignored generated modules. This keeps zero runtime I/O, is bundler-agnostic, and removes the manual duplication that currently drifts. Codegen was chosen over `@module` (brittle 4-segment relative path into `lib/`) and runtime-`fs` (`en.json` is not shipped).

## Requirements

### Requirement: REQ-CODEGEN-1 — Schema JSON emitted via %raw

`scripts/codegen.mjs` MUST read `schemas/quotas.schema.json` and emit `src/Infra/ConfigLoader.Schema.res` embedding the JSON verbatim using `%raw` (the same primitive `ConfigLoader.res` already uses).

#### Scenario: Happy path — schema generated

- GIVEN the canonical `schemas/quotas.schema.json` exists
- WHEN `scripts/codegen.mjs` runs
- THEN `src/Infra/ConfigLoader.Schema.res` is written embedding the JSON via `%raw`
- AND the embedded JSON equals the canonical file byte-for-byte (modulo formatting)

### Requirement: REQ-CODEGEN-2 — Locale JSON emitted via Dict.fromArray

`scripts/codegen.mjs` MUST read `src/i18n/locales/en.json` and emit `src/i18n/Translator.EnCatalog.res` exposing the entries via `Dict.fromArray` (the same primitive `Translator.res` already uses).

#### Scenario: Happy path — locale generated

- GIVEN the canonical `src/i18n/locales/en.json` exists
- WHEN `scripts/codegen.mjs` runs
- THEN `src/i18n/Translator.EnCatalog.res` is written using `Dict.fromArray`
- AND the catalog keys/values match the canonical `en.json`

### Requirement: REQ-CODEGEN-3 — Generated files are git-ignored

Both generated modules (`ConfigLoader.Schema.res`, `Translator.EnCatalog.res`) MUST be listed in `.gitignore`. The canonical JSON files remain the only committed source of truth.

#### Scenario: Happy path — git ignores generated modules

- GIVEN codegen has produced both generated `.res` files
- WHEN `git status` is run
- THEN neither generated file appears as an untracked or modified file

### Requirement: REQ-CODEGEN-4 — Codegen is idempotent

Running `scripts/codegen.mjs` twice in succession MUST produce byte-identical output for both generated files (deterministic key ordering, no timestamps, no nondeterminism).

#### Scenario: Happy path — re-run is a no-op diff

- GIVEN codegen has already produced both generated files
- WHEN `scripts/codegen.mjs` is run a second time
- THEN both generated files are unchanged (zero-byte diff)
- AND the script exits `0`

### Requirement: REQ-CODEGEN-5 — Round-trip safety for schema

A round-trip safety check MUST hold: parsing the JSON embedded in the generated `ConfigLoader.Schema.res` MUST equal the canonical `schemas/quotas.schema.json` (same object structure and values).

#### Scenario: Happy path — round-trip equality

- GIVEN `ConfigLoader.Schema.res` was generated from the canonical schema
- WHEN the embedded JSON is extracted and parsed
- THEN the parsed object deep-equals the canonical `quotas.schema.json`

#### Scenario: Failure path — drift detected

- GIVEN the canonical schema JSON is edited but codegen has not re-run
- WHEN a round-trip check compares the generated `%raw` content to the canonical file
- THEN the check reports drift and fails (codegen must be re-run)

### Requirement: REQ-CODEGEN-6 — Consumer modules import generated modules

`ConfigLoader.res` and `Translator.res` MUST import from the generated modules (`ConfigLoader.Schema.res`, `Translator.EnCatalog.res`) instead of inlining the `%raw` / `Dict.fromArray` literals.

#### Scenario: Happy path — consumers use generated modules

- GIVEN codegen has produced both generated modules
- WHEN `rescript build` compiles `ConfigLoader.res` and `Translator.res`
- THEN both modules resolve their schema/catalog from the generated modules
- AND no inline `%raw`-JSON or `Dict.fromArray`-literal remains in the consumer modules

## Cross-capability invariants

- **INV-1 (vitest-stays-green-until-phase-5)**: Codegen is introduced in phase 4 as an additive change. The existing vitest suite MUST remain green after the consumer modules switch to importing generated modules; the generated output must reproduce the previously-inlined behavior.
- **INV-2 (no CLI behavior change)**: Codegen produces behaviorally identical asset modules to the current inlined versions. `dist/cli/index.js` MUST keep the same render output and exit codes — the schema and locale catalog values are unchanged, only their source location moves from inline literals to generated modules.
