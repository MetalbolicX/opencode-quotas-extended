# Archive Report — `rescript-cutover`

```yaml
schema: gentle-ai.sdd-archive/v1
changeName: rescript-cutover
archivedAt: 2026-07-30
status: CLOSED ✅
cycleDuration: N/A (no prior SDD baseline)
artifactStore: hybrid
```

## Cycle Summary

The `rescript-cutover` SDD cycle executed a full production cutover from dual TypeScript+ReScript to ReScript-only, spanning 7 work units (WU-1 → WU-7) across 34 commits on `main`. The change introduced deterministic asset codegen (`scripts/codegen.mjs`), an aggregate ReScript test runner (`scripts/run-tests.mjs`), wired both into the `package.json` lifecycle, archived all 46 TypeScript source files to `legacy/`, dropped Vitest, and updated operational documentation. All five verification gates were green (47/47 ReScript tests, clean `res:build`, clean `build`, CLI smoke, secret-leak hygiene). INV-1 (vitest-stays-green-through-phase-5) was satisfied and closed; INV-2 (no CLI behavior change) was preserved throughout. Three non-blocking warnings (W-1: empty `tests/` directory, W-2: missing ReScript runner-safety self-tests, W-3: missing build-lifecycle self-tests) are documented for follow-up.

## Phase Pointer (Audit Trail)

| Phase | Artifact | Status |
|---|---|---|
| Proposal | `openspec/changes/archive/2026-07-30-rescript-cutover/proposal.md` | ✅ |
| Spec | `openspec/specs/{build-pipeline,test-runner,asset-codegen}/spec.md` | ✅ (synced to main) |
| Spec (delta) | `openspec/changes/archive/2026-07-30-rescript-cutover/specs/` | ✅ (archived) |
| Design | `openspec/changes/archive/2026-07-30-rescript-cutover/design.md` | ✅ |
| Tasks | `openspec/changes/archive/2026-07-30-rescript-cutover/tasks.md` | ✅ |
| Apply | `openspec/changes/archive/2026-07-30-rescript-cutover/apply-progress.md` | ✅ |
| Verify | `openspec/changes/archive/2026-07-30-rescript-cutover/verify-report.md` | ✅ |
| Archive | `openspec/changes/archive/2026-07-30-rescript-cutover/archive-report.md` | ✅ (this file) |

## Specs Synced to Main

| Domain | Action | Details |
|--------|--------|---------|
| `build-pipeline` | Created | 4 requirements, 6 scenarios — REQ-PIPELINE-1..4 |
| `test-runner` | Created | 5 requirements, 8 scenarios — REQ-TEST-1..5 |
| `asset-codegen` | Created | 6 requirements, 7 scenarios — REQ-CODEGEN-1..6 |

These are the first specs committed for this project under OpenSpec; no prior baseline existed.

## Engram Observation IDs (Traceability)

| Artifact | Topic Key | Observation ID |
|---|---|---|
| Decision record | `sdd/rescript-cutover/decision` | #3911 |
| Proposal | `sdd/rescript-cutover/proposal` | #3912 |
| Spec | `sdd/rescript-cutover/spec` | #3913 |
| Design | `sdd/rescript-cutover/design` | #3915 |
| Tasks | `sdd/rescript-cutover/tasks` | #3918 |
| Apply-progress milestones | `sdd/rescript-cutover/apply-progress` | #3919+ |
| Latent failures | `sdd/rescript-cutover/latent-failures` | #3923 |
| Verify-report | `sdd/rescript-cutover/verify-report` | #3925 |

## Final Verification Stats

| Gate | Result |
|---|---|
| `pnpm test` (47/47 ReScript tests) | ✅ Exit 0 |
| `pnpm res:build` | ✅ Clean (0 warnings) |
| `pnpm build` | ✅ Produces `dist/cli/index.js` (93.7 kB) |
| `node dist/cli/index.js --help` | ✅ Exit 0, output matches INV-2 |
| `bash scripts/check-secrets.sh` | ✅ Exit 0 |
| `node scripts/codegen.mjs --check` | ✅ Exit 0 (no drift) |

## Commit Summary

- **Total commits:** 34 (across 8 work units, multiple sub-slices)
- **Authored-line budget:** All WU commits ≤400 lines (WU-6 deletion batches excluded per plan)
- **Files committed:** ~25 core commits + 16 WU-6 sub-commits
- **Chain strategy:** Stacked-to-main (all WUs merged to `origin/main`)

## Invariants

| Invariant | Status | Evidence |
|---|---|---|
| INV-1 (vitest stays green until phase 5) | ✅ CLOSED | Vitest 726/726 passed through WU-5; WU-6 deleted vitest only after WU-4b parity gate confirmed. |
| INV-2 (no CLI behavior change) | ✅ PRESERVED | `E2eSmokeTests.res` 9/9 pass; `CliEntrypointTests.res` 3/3 pass; `--help`, `-h`, `--list`, `-p`, `-m` all exit 0 with unchanged output. |

## Outstanding Warnings (Non-Blocking)

| ID | Severity | Description | Suggested Follow-Up |
|---|---|---|---|
| W-1 | NON-BLOCKING | Empty `tests/` directory remains as untracked artifact (0 files, not tracked by git, functionally inert) | `rmdir tests` or add `tests/` to `.gitignore` if top-level tests dir is desired |
| W-2 | NON-BLOCKING | REQ-TEST-2 crash/timeout and REQ-TEST-3 fail-fast paths have correct runner code but no in-tree automated ReScript self-test asserting those paths | Create `src/architecture/RunnerSafetyTests.res` (~150 lines) |
| W-3 | NON-BLOCKING | REQ-PIPELINE-2 fail-fast and REQ-PIPELINE-3 postinstall scenarios have correct `package.json` wiring but no automated ReScript self-test | Create `src/architecture/BuildLifecycleTests.res` (~100 lines) |

## Suggestions (Follow-Up Changes)

| ID | Description | Estimated Effort |
|---|---|---|
| S-1 | Port runner-safety + build-lifecycle ReScript tests (covers W-2, W-3) | ~150–250 lines |
| S-2 | Align `scripts/run-tests.mjs` comment (line 15: "exits 0" → "exits 1") with actual code | Trivial (1 line) |
| S-3 | Add `bisect_ppx` coverage instrumentation (follow-up change, out of scope per proposal) | Out of scope |
| S-4 | Tighten design.md §run-tests.mjs `stdio` description to match `pipe + relay` implementation | Trivial (docs only) |

## What Was Delivered

- **ReScript-only production source** — zero TypeScript files in `src/`; 46 TS files archived to `legacy/`
- **Deterministic asset codegen** — `scripts/codegen.mjs` reads canonical JSON, emits git-ignored `.res` modules; wired to `prebuild`/`preres:build`/`postinstall`
- **Aggregate ReScript test runner** — `scripts/run-tests.mjs` discovers `*Tests.res.mjs` + `*.test.res.mjs`, spawns children, aggregates exit codes; sole `pnpm test` command
- **`legacy/` archive** — 46 archived TS files + 1 copied `en.json` (47 total), committed, not ignored, fully reversible via `git revert`
- **Operational documentation** — `README.md` and `CLAUDE.md` reflect ReScript + rolldown production stack

## Rollback

One `git revert <WU-5 commit>` restores the entire TypeScript tree, vitest suite, and pre-cutover `package.json` configuration. Generated files are git-ignored and regenerated on next build. INV-2 rollback is bounded by the WU-4b parity receipt and the WU-6e2e smoke harness evidence.

## SDD Cycle Complete

The `rescript-cutover` change has been fully planned (proposal), specified (delta specs), designed, tasked (7 WUs), implemented (34 commits), verified (47/47 tests, all gates green), and archived. The production stack is now ReScript + rolldown; Vitest is removed; `legacy/` preserves the archived TypeScript source. Ready for the next change.

---

**Archive location:** `openspec/changes/archive/2026-07-30-rescript-cutover/`
**Main specs:** `openspec/specs/{build-pipeline,test-runner,asset-codegen}/spec.md`
**Engram topic:** `sdd/rescript-cutover/archive-report` (type: `architecture`)
