# Test Runner Specification

## Purpose

A unified Node-based test runner (`scripts/run-tests.mjs`, exposed as `pnpm test:res`) aggregates pass/fail across all compiled ReScript test files. It globs `lib/es6/**/*Tests.res.mjs` and `lib/es6/**/*.test.res.mjs`, spawns each as a child process (each file calls `process.exit` after `runTests()`), and aggregates exit codes into a single pass/fail result. During phases 1–4 it runs green **alongside** vitest; it replaces vitest only in phase 5 after parity is proven.

## Requirements

### Requirement: REQ-TEST-1 — Runner globs compiled test modules

The runner MUST discover compiled ReScript test modules by globbing `lib/es6/**/*Tests.res.mjs` and `lib/es6/**/*.test.res.mjs`.

#### Scenario: Happy path — discovers test files

- GIVEN `rescript build` has produced `lib/es6/` test modules
- WHEN `pnpm test:res` is invoked
- THEN the runner collects every `*Tests.res.mjs` and `*.test.res.mjs` file under `lib/es6/`
- AND at least one test file is found

#### Scenario: Edge case — no test files found

- GIVEN `lib/es6/` contains no matching test modules
- WHEN `pnpm test:res` is invoked
- THEN the runner reports zero files and exits non-zero (no silent pass)

### Requirement: REQ-TEST-2 — Each file runs as a child process with aggregated exit codes

The runner MUST execute each discovered test file as a separate Node child process. Because each compiled test module calls `process.exit` after `runTests()`, the runner SHALL collect each child's exit code and aggregate them.

#### Scenario: Happy path — all children pass

- GIVEN three compiled test files, all of which call `process.exit(0)`
- WHEN the runner spawns each as a child process
- THEN all three exit `0`
- AND the runner's aggregate result is pass

#### Scenario: Edge case — child crashes or times out

- GIVEN a test file whose process exits non-zero (assertion failure) or never exits
- WHEN the runner spawns it
- THEN the child is recorded as failed
- AND the aggregate result is fail

### Requirement: REQ-TEST-3 — Runner exits non-zero on any child failure

The runner MUST exit with a non-zero status code if ANY child test process fails. It SHALL exit `0` only when every child exits `0`.

#### Scenario: Failure path — one failing file fails the run

- GIVEN five test files where exactly one exits non-zero
- WHEN the runner aggregates results
- THEN the runner exits non-zero
- AND the failing file is identified in the output

### Requirement: REQ-TEST-4 — Per-file pass/fail summary

The runner SHOULD print a per-file pass/fail summary so failures are attributable to a specific compiled test module.

#### Scenario: Happy path — summary lists every file

- GIVEN the runner has executed all discovered test files
- WHEN the run completes
- THEN a summary lists each file with its pass/fail status
- AND the total counts (files run, passed, failed) are printed

### Requirement: REQ-TEST-5 — Vitest remains green in parallel through phase 4

During phases 1–4, BOTH `pnpm test` (vitest) and `pnpm test:res` (this runner) MUST run green side-by-side. The runner MUST NOT alter, disable, or break the vitest suite. Vitest is removed ONLY in phase 5 after parity is proven.

#### Scenario: Integration with INV-1 — both runners green

- GIVEN the change is at any point in phases 1–4
- WHEN `pnpm test` (vitest) and `pnpm test:res` are each invoked
- THEN both runners report all-green
- AND the new runner has not modified any vitest test file or configuration

#### Scenario: INV-1 gate — vitest still the behavior guard

- GIVEN the ReScript runner reports green but a vitest test fails
- WHEN phase 4 parity is being evaluated
- THEN the cutover to phase 5 (vitest removal) MUST NOT proceed until parity is restored

## Cross-capability invariants

- **INV-1 (vitest-stays-green-until-phase-5)**: This runner is ADDITIVE through phase 4 — it MUST coexist with a green vitest suite. Vitest remains the behavior gate; the new runner does not replace it until phase 5 (see REQ-TEST-5).
- **INV-2 (no CLI behavior change)**: The test runner is infrastructure only. It MUST NOT change `dist/cli/index.js` behavior — same flags, render output, and exit codes for the same inputs.
