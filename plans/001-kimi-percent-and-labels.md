# Plan 001: Kimi table shows labeled rows rendered as percentages, matching the Kimi web page

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat ed6ef87..HEAD -- src/Providers/CodingPlanParse.res src/Providers/Kimi.res src/rendering/SemanticLabels.res src/i18n/locales/en.json src/Providers/CodingPlanParseTests.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `ed6ef87`, 2026-08-16

## Why this matters

The Kimi provider currently renders two anonymous rows with a hardcoded
`"requests"` unit:

```
|  [..........]  1 / 100 requests            7d     -      |
|  [█.........]  5 / 100 requests            31m    -      |
```

Two defects, both confirmed against the live API on 2026-08-16:

1. **The unit is fabricated.** The live response of
   `GET https://api.kimi.com/coding/v1/usages` contains NO unit field
   anywhere — only `used`/`limit`/`remaining` (numeric strings) and
   `resetTime`. `"requests"` is an unverifiable assumption made when the
   parser was written. The Kimi web page presents these same numbers as a
   percentage; our own OpenAI and Minimax providers already model this
   correctly with `unit: "%"`, which the table renderer presents as
   `X% used`.
2. **The rows are unlabeled.** The table's first 24-char column renders
   `quotaData.info`; Kimi rows set `info: None`, so the column is blank and
   the user cannot tell which row is the weekly quota vs the 5-hour window.
   The i18n keys `concept.kimi-weekly-usage` and `concept.kimi-5h-rolling`
   already exist in `src/i18n/locales/en.json` but were never wired.

After this plan, the table shows labeled, percentage-rendered rows:

```
| Kimi weekly usage     [..........]   1% used                  7d     -      |
| Kimi 5h rolling limit [█.........]   5% used                  31m    -      |
```

(exact spacing determined by existing renderer width logic — do not tune
widths). JSON output keeps raw `used`/`limit` counts (data fidelity) and
reports `"unit": "%"`, consistent with existing OpenAI/Minimax `%` rows.

Out of scope and rejected: monthly usage. The live response's
`totalQuota` field is `{}` (empty) — the endpoint exposes only the 7-day
summary and the 5-hour window. Nothing to add.

## Current state

- `src/Providers/CodingPlanParse.res` — shared parser for coding-plan
  providers; contains Kimi row construction. Two sites hardcode the unit
  and blank the label:
  - `summaryToQuota` (~line 472-504) builds the weekly row:
    ```rescript
    Some({
      id: `${idPrefix}-weekly`,
      providerName,
      used: effectiveUsed,
      limit: l,
      unit: "requests",          // LINE ~498 — change to "%"
      reset: parseIsoReset(d, "resetTime"),
      window: #rollingWeekly,
      info: None,                // LINE ~501 — change to Some(label)
      modelId: None,
    })
    ```
  - `limitRowToQuota` (~line 508-566) builds per-window rows (300min →
    `kimi-5h`):
    ```rescript
    Some({
      id,                        // e.g. "kimi-5h"
      providerName,
      used: effectiveUsed,
      limit: l,
      unit: "requests",          // LINE ~553 — change to "%"
      reset: parseIsoReset(detailDict, "resetTime"),
      window,                    // e.g. #rolling5h
      info: None,                // LINE ~556 — change to Some(label)
      modelId: None,
    })
    ```
  - `parseKimiUsages(~json, ~idPrefix, ~providerName)` (~line 570-597) is
    the entry point called from `src/Providers/Kimi.res:51-56`:
    ```rescript
    Promise.resolve(CodingPlanParse.parseKimiUsages(
      ~json,
      ~idPrefix="kimi",
      ~providerName="Kimi / Moonshot"
    ))
    ```
- `src/rendering/Renderers.res:110-137` — `usageText(q, ratio)`. The `%`
  branch already exists; NO renderer change is needed:
  ```rescript
  | "%" =>
    switch q.limit {
    | None => "unlimited"
    | Some(_) =>
      let pct = Math.round(Belt.Option.getWithDefault(ratio, 0.0) *. 100.0)
      `${Float.toString(pct)}% used`
    }
  ```
- `src/rendering/SemanticLabels.res` — defines
  `enrichQuotaLabel(providerId, config)` returning
  `{ concept: string, label: string }`; translation is resolved module-wide
  (no translator parameter).
- `src/Providers/Minimax.res` — the exemplar info-label pattern. Module has
  `open SemanticLabels` (line 6); call site (~lines 128-150):
  ```rescript
  let intervalConcept = enrichQuotaLabel(
    "minimax",
    {
      type_: None,
      unit: None,
      number: None,
      modelName: Some("general"),
      weekly: Some(false),
      openaiVariant: None,
      geminiModel: None,
    },
  )
  // ...
  info: Some(intervalConcept.label),
  ```
- `src/i18n/locales/en.json` — keys already present (values are final, do
  not edit this file unless a key is missing):
  ```json
  "concept.kimi-weekly-usage": "Kimi weekly usage",
  "concept.kimi-5h-rolling": "Kimi 5h rolling limit"
  ```
- `src/Providers/CodingPlanParseTests.res` — existing assertions that pin
  the old behavior and must be updated:
  - ~line 1227: `test("parseKimiUsages every row has unit requests"` —
    asserts `unit == "requests"`
  - ~line 1247: another assertion that every row has unit `"requests"`
  - No existing assertions on Kimi `info` (it was always `None`).
- Generated file warning: `src/i18n/Translator/EnCatalog.res` is generated
  from `en.json` by `pnpm codegen` and is git-ignored — NEVER edit it
  directly. If you add a locale key, it regenerates on build.
- Repo conventions: ReScript 12, pnpm, tests are plain `.res` test files
  run via `scripts/run-tests.mjs`. Write assertions in the existing style
  of `CodingPlanParseTests.res`. This repo requires a test-first or
  test-with-change discipline for non-trivial edits (per `CLAUDE.md`).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Full build | `pnpm build` | exit 0, bundle at `dist/cli/index.js` |
| All tests | `pnpm test` | exit 0, 47 test files pass |
| Codegen check | `pnpm codegen --check` | exit 0 |
| Secret gate | `bash scripts/check-secrets.sh` | exit 0 |
| Live smoke (needs local kimi credential) | `node dist/cli/index.js -p kimi -m table` | two labeled rows showing `X% used` |

## Scope

**In scope** (the only files you should modify):
- `src/Providers/CodingPlanParse.res`
- `src/Providers/Kimi.res` (only if step 2's wiring belongs there)
- `src/rendering/SemanticLabels.res` (only if kimi mapping is missing)
- `src/i18n/locales/en.json` (only if a needed key is missing)
- `src/Providers/CodingPlanParseTests.res` (update + extend)

**Out of scope** (do NOT touch):
- `src/rendering/Renderers.res` — the `%` branch already renders exactly
  what we need; renderer changes would affect all providers.
- Any other provider, the CLI, the pipeline, or `legacy/`.
- Monthly/window logic beyond the two existing rows.
- `src/i18n/Translator/EnCatalog.res` — generated file.

## Git workflow

- Branch: stay on the current branch (repo works directly on main).
- Commit style: conventional commits, e.g.
  `fix(kimi): render usage as percentage and label quota rows`.
  See `git log --oneline -10` for examples (`feat(providers): ...`,
  `test(providers): ...`).
- Do NOT push unless instructed.

## Steps

### Step 1: Flip the Kimi unit from "requests" to "%"

In `src/Providers/CodingPlanParse.res`, change `unit: "requests"` →
`unit: "%"` in BOTH `summaryToQuota` (~line 498) and `limitRowToQuota`
(~line 553).

In `src/Providers/CodingPlanParseTests.res`, update the two assertions
(~lines 1227 and 1247) that expect `"requests"` to expect `"%"` instead
(keep the test names accurate — rename e.g. "every row has unit requests"
→ "every row has unit percent").

**Verify**: `pnpm build && pnpm test` → exit 0, all 47 files pass.

### Step 2: Wire the row labels into `info`

First INSPECT: grep `kimi` in `src/rendering/SemanticLabels.res`.

- **Case A — kimi mapping exists** (likely; the concept keys were added in
  commit b47d75f): in `CodingPlanParse.res`, set `info` at the two row
  construction sites using the Minimax pattern:
  - In `summaryToQuota` (weekly row): call
    `enrichQuotaLabel("kimi", <config that selects the weekly concept>)`
    and set `info: Some(concept.label)`. Match whatever config shape the
    kimi branch of `SemanticLabels` expects — mirror the Minimax call at
    `Minimax.res:128-138` (`weekly: Some(true)` for the weekly row).
  - In `limitRowToQuota` (5h row): same, with the config selecting the 5h
    concept (`weekly: Some(false)`).
- **Case B — no kimi mapping**: extend `SemanticLabels.res` with a kimi
  branch modeled directly on the minimax branch, emitting the two existing
  concept keys `concept.kimi-weekly-usage` / `concept.kimi-5h-rolling`
  (do not invent new key names). Then proceed as Case A.

Add `open SemanticLabels` (or a qualified import) at the top of
`CodingPlanParse.res` if not already present — check its current imports
first and follow the file's existing import style.

If `enrichQuotaLabel` cannot be called from the shared parser for some
structural reason (e.g. it must run after credential resolution), fall
back to post-processing in `src/Providers/Kimi.res:51-56`: map over the
rows returned by `parseKimiUsages` and set `info` by row id
(`kimi-weekly` → weekly label, `kimi-5h` → 5h label) before
`Promise.resolve`.

**Verify**: `pnpm build` → exit 0. Then
`node dist/cli/index.js -p kimi -m table` → both rows show a label in the
first column ("Kimi weekly usage" / "Kimi 5h rolling limit") and `X% used`
in the usage column. If no local kimi credential is available, verify via
unit test instead (Step 3) and note it in your report.

### Step 3: Extend the parser tests

In `src/Providers/CodingPlanParseTests.res`, using the existing Kimi
fixture (the `parseKimiUsages` tests around lines 1227-1247):

- Assert the weekly row has `info: Some("Kimi weekly usage")` (or the
  label string the translator resolves at test time — match how Minimax
  label assertions are written in `src/Providers/MinimaxTests.res`; if
  Minimax tests assert on the English label string, do the same).
- Assert the 5h row has `info: Some("Kimi 5h rolling limit")`.
- Keep the existing unit assertions (now `%`) intact.

**Verify**: `pnpm build && pnpm test` → exit 0, 47 files pass, including
the updated Kimi tests.

## Test plan

- Updated: unit assertions `requests` → `%` (~lines 1227, 1247).
- New: info-label assertions for both rows (weekly + 5h), modeled on the
  Minimax label-assertion style in `src/Providers/MinimaxTests.res`.
- Regression safety: no other provider's tests touch the Kimi parser, so a
  green full run (`pnpm test`, 47 files) plus the live smoke covers it.

## Done criteria

ALL must hold:

- [ ] `pnpm build` exits 0
- [ ] `pnpm test` exits 0 (47 files)
- [ ] `pnpm codegen --check` exits 0
- [ ] `bash scripts/check-secrets.sh` exits 0
- [ ] `grep -n '"requests"' src/Providers/CodingPlanParse.res` returns no
      matches
- [ ] `node dist/cli/index.js -p kimi -m table` (with credential) shows
      two labeled rows with `X% used`; without credential, unit tests
      prove it
- [ ] `node dist/cli/index.js -p kimi -m json` reports `"unit": "%"` on
      both rows and unchanged numeric `used`/`limit`
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpts in "Current state" do not match the live code (drift).
- `enrichQuotaLabel` signature differs from
  `(providerId: string, config)` — do not guess the call shape.
- Wiring labels inside the parser breaks OTHER providers that share
  `CodingPlanParse` (e.g. z.ai tests fail) — report before touching their
  code.
- A step's verification fails twice after a reasonable fix attempt.
- The live API response shape changed (e.g. `usage`/`limits` missing) —
  do not "fix" the parser to match a new envelope on your own.

## Maintenance notes

- If Kimi later populates `totalQuota` (monthly usage), add a third row in
  `parseKimiUsages` following the same pattern; the concept key
  (e.g. `concept.kimi-monthly-usage`) must be added to `en.json` and will
  flow into generated `EnCatalog.res` via codegen.
- A reviewer should scrutinize: (1) the `%` unit now flows to the JSON
  output — confirm parity with OpenAI/Minimax `%` rows is acceptable;
  (2) that no other coding-plan provider shares the two changed unit
  sites (z.ai has its own row constructors — verify lines ~498/553 are
  Kimi-only before editing).
- Deferred: showing `remaining` (API provides it; we derive it as
  limit-used implicitly) and the `parallel` concurrency limit — neither is
  user-requested.
