# Build Pipeline Specification

## Purpose

Establish the ReScript → rolldown chain as the sole production build for `dist/cli/index.js`. A codegen preflight emits generated asset modules, then `rescript build` compiles, then `rolldown` bundles. The chain is wired into `package.json` scripts (`prebuild`, `preres:build`, `postinstall`) so the build is deterministic and fresh installs are bootstrapped. The shipped CLI's observable behavior MUST NOT change — only build/test infrastructure does.

## Requirements

### Requirement: REQ-PIPELINE-1 — Codegen preflight before ReScript build

A codegen step (`scripts/codegen.mjs`) MUST run before `rescript build` so the generated asset modules exist before the ReScript compiler reads them. The system SHALL expose this as a `preres:build` hook so any `rescript build` invocation regenerates assets.

#### Scenario: Happy path — codegen precedes rescript build

- GIVEN the generated `.res` asset modules are absent or stale
- WHEN `pnpm build` is invoked
- THEN `scripts/codegen.mjs` runs to completion before `rescript build` starts
- AND the generated modules exist on disk before the compiler reads them

#### Scenario: Manual rescript build regenerates assets

- GIVEN a developer runs `pnpm res:build` directly
- WHEN the `preres:build` hook fires
- THEN codegen runs first and the assets are regenerated before compilation

### Requirement: REQ-PIPELINE-2 — pnpm build chains the three stages in order

`pnpm build` MUST execute codegen → `res:build` → `rolldown` in that exact order. The chain SHALL fail fast: if any stage exits non-zero, no later stage runs.

#### Scenario: Happy path — full chain succeeds

- GIVEN a clean checkout with canonical JSON assets present
- WHEN `pnpm build` is invoked
- THEN codegen runs, then `res:build` compiles, then `rolldown` bundles
- AND `dist/cli/index.js` is produced with a Node shebang

#### Scenario: Failure fast — rolldown does not run on rescript failure

- GIVEN `rescript build` exits non-zero (e.g. a type error)
- WHEN `pnpm build` is invoked
- THEN the build aborts before rolldown runs
- AND the overall `pnpm build` exits non-zero

### Requirement: REQ-PIPELINE-3 — postinstall bootstraps generated assets

`pnpm postinstall` MUST run codegen so a fresh `pnpm install` produces the generated asset modules without an explicit build step.

#### Scenario: Fresh install has generated assets

- GIVEN a fresh clone with no generated `.res` files
- WHEN `pnpm install` completes (triggering `postinstall`)
- THEN the generated asset modules exist on disk and are ready for compilation

### Requirement: REQ-PIPELINE-4 — Shipped CLI behavior is unchanged

The produced `dist/cli/index.js` MUST remain functionally byte-equivalent in observable behavior to the pre-cutover binary for the same inputs: same flags, same render output, same exit codes.

#### Scenario: CLI smoke test is byte-identical

- GIVEN a working `dist/cli/index.js` produced by the new chain
- WHEN `node dist/cli/index.js --help` is run before and after the change
- THEN the help output is identical
- AND the exit code is `0` in both cases

## Cross-capability invariants

- **INV-1 (vitest-stays-green-until-phase-5)**: During phases 1–4 the pipeline MUST NOT disable or break `pnpm test` (vitest). The new build scripts coexist with the existing vitest suite; both stay green until the vitest removal in phase 5.
- **INV-2 (no CLI behavior change)**: This capability changes build/test infrastructure only. `dist/cli/index.js` observable behavior (flags, render output, exit codes) MUST be unchanged (see REQ-PIPELINE-4).
