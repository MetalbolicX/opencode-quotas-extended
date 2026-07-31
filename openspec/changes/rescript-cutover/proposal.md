# Proposal: ReScript Production Cutover

## Intent

Eliminate the dual TS+ReScript implementation. The 45 TS source files are **dead production code** — `rolldown.config.ts` bundles `lib/es6/src/Bootstrap.res.mjs`, never `src/cli/index.ts`. Carrying two implementations, two test runners (vitest 641 + ReScript), and inlined duplicated assets (`%raw` schema, `Dict.fromArray` locale) is ongoing debt. Cutover to a single ReScript source of truth, a codegen-backed asset pipeline, and a ReScript test runner.

## Architectural Constraints (locked decisions)

1. **Archive TS** to `legacy/` — preserve structure, no deletion.
2. **Migrate tests to ReScript runner, drop vitest.** Translate vitest→ReScript BEFORE removing vitest; parallel-run parity is the mandatory proof.
3. **Replace inlined-asset duplication via codegen.** `scripts/codegen.mjs` reads canonical JSON, emits git-ignored generated `.res` via existing `%raw`/`Dict.fromArray`. Single source of truth, zero runtime I/O, bundler-agnostic.

## Scope

### In Scope
- ReScript test runner (`scripts/run-tests.mjs` → `pnpm test:res`).
- Port 6 architecture guards → `*Tests.res`; drop 2 moot (vitest-thresholds, domain.parity).
- Fill ~5–10 unit + 3 integration test gaps; verify 5 uncertain-parity modules.
- Asset codegen wired to `prebuild`/`preres:build`/`postinstall`.
- Archive 45 TS → `legacy/`; drop `tests/`, vitest config/deps; rewrite `package.json`.
- Update `README.md` + `CLAUDE.md`.

### Out of Scope
- bisect_ppx / coverage instrumentation; keeping vitest post-cutover; any behavioral change to shipped `dist/cli/index.js`; ETTL history wiring; web-scraping providers.

## Capabilities

### New Capabilities
- `build-pipeline`: codegen prebuild → `rescript build` → rolldown → `dist/cli/index.js`.
- `test-runner`: Node glob runner over `lib/es6/**/*Tests.res.mjs` (+ `*.test.res.mjs`) replacing vitest; aggregates child-process results.
- `asset-codegen`: single-source-of-truth codegen for `schemas/quotas.schema.json` + `src/i18n/locales/en.json`.

### Modified Capabilities
None — shipped CLI behavior is unchanged (specs/ has no existing capabilities).

## Approach (7 phases, additive-first)

1. Build `scripts/run-tests.mjs` → `pnpm test:res`. **Vitest keeps running.**
2. Port 6 architecture guards → `*Tests.res` (via `Node.fs`/`Node.execSync`); drop 2 moot.
3. Fill unit/integration test gaps. **Run BOTH runners side-by-side; confirm parity.**
4. Add `scripts/codegen.mjs`; wire prebuild/preres:build/postinstall; update `ConfigLoader.res` + `Translator.res` to import generated modules.
5. **Cutover (irreversible):** archive 45 TS → `legacy/`; drop `tests/`, vitest, `typecheck`; `build`=`codegen && res:build && rolldown`; `test`=`run-tests.mjs`.
6. Rewrite `README.md` + `CLAUDE.md` (ReScript + rolldown stack; note `legacy/`).
7. Final gates.

> **MANDATORY invariant:** vitest stays green and is the behavior gate **through phase 4**. Phase 5 (deletion) runs ONLY after the ReScript runner is proven equivalent. Phases 1–4 are additive (no deletions) — project stays green, old tests keep guarding.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `scripts/run-tests.mjs`, `scripts/codegen.mjs` | New | Test runner + asset codegen |
| `ConfigLoader.res`, `Translator.res` | Modified | Import generated modules vs inlined `%raw`/`Dict.fromArray` |
| `src/**/*Tests.res` | New/Modified | Ported guards + gap tests |
| `tests/`, `src/**/*.ts` (45 files) | Removed | → `legacy/` (phase 5 only) |
| `package.json`, `README.md`, `CLAUDE.md` | Modified | Scripts + stack docs |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Test-parity gap (44 TS vs ~36 Res) | Med | Side-by-side run through phase 4; no deletion until proven equal |
| Generated-file drift | Low | codegen in prebuild/postinstall; generated files git-ignored; canonical JSON is source |
| Coverage-threshold loss (vitest thresholds dropped) | Med | New runner aggregates pass/fail; revisit threshold post-cutover |
| `@module`/fs asset path brittleness | — | Avoided: codegen chosen over brittle `@module` (4-seg deep) and locale-publish-dependent fs |

## Rollback Plan

Phases 1–4 additive — revert by deleting new files; vitest/TS untouched. Phase 5 is a single cutover commit: `git revert` restores `src/**/*.ts`, `tests/`, vitest config/deps, `package.json`. Generated files are git-ignored.

## Dependencies
None — ReScript 12.3.0, rolldown, Node 18+ already present.

## Success Criteria
- [ ] `rescript build` clean (zero warnings).
- [ ] `pnpm test:res` all green; parity vs prior vitest confirmed.
- [ ] `pnpm build` succeeds (`codegen && res:build && rolldown`).
- [ ] `node dist/cli/index.js --help` smoke passes — **byte-identical CLI behavior** (no behavioral change).
- [ ] Secret-leak gate green.
- [ ] vitest green through phase 4; removed cleanly in phase 5.
- [ ] `legacy/` preserves TS structure.
