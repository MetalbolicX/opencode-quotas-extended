# Plan 009: Map z.ai pro-plan rows to MCP / 5h rolling window / Weekly limit

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat f548fd4..HEAD -- src/Providers/CodingPlanParse/ZaiParser.res src/Providers/CodingPlanParseTests.res src/rendering/SemanticLabels.res src/i18n/locales/en.json`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (plans 001–008 do not conflict; 005 already split the parser into `ZaiParser.res`)
- **Category**: bug
- **Planned at**: commit `f548fd4`, 2026-09-14

## Why this matters

The operator upgraded their z.ai coding plan from `lite` to `pro`. The live API
now reports `data.level: "pro"` and returns the same unit-coded quota entries
as lite, but the parser only applies semantic row titles when
`level === "lite"`. Every pro row therefore renders as the generic fallback
`"Token quota #N"` (and the MCP row mislabels as `"5h rolling window"`), with
no stable MCP → 5h → weekly ordering. After this plan, the z.ai table shows
exactly three correctly titled, correctly ordered rows: **MCP quota**,
**5h rolling window**, **Weekly limit** (the operator explicitly chose
"Weekly limit" over the current "Weekly quota").

## Current state

Files and roles:

- `src/Providers/CodingPlanParse/ZaiParser.res` (210 lines) — maps z.ai API
  limit entries to `QuotaData` rows; decides window type, row title, sort.
- `src/Providers/CodingPlanParseTests.res` (~806 lines) — parser tests,
  including two that pin the CURRENT (wrong-for-pro) fallback behavior.
- `src/rendering/SemanticLabels.res` — concept → label table (`labelMap`).
- `src/i18n/locales/en.json` — locale strings; mirrored into the git-ignored,
  codegen'd `src/i18n/Translator/EnCatalog.res` by `scripts/codegen.mjs`.

Verified live pro API response (2026-09-14, endpoint
`https://api.z.ai/api/monitor/usage/quota/limit`):

```json
{ "data": { "level": "pro", "limits": [
  { "type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 1, "nextResetTime": 1789455747809 },
  { "type": "TOKENS_LIMIT", "unit": 6, "number": 1, "percentage": 1, "nextResetTime": 1790042247981 },
  { "type": "TIME_LIMIT", "unit": 5, "number": 1, "usage": 1000, "currentValue": 0,
    "remaining": 1000, "percentage": 0, "nextResetTime": 1792029447999,
    "usageDetails": [ { "modelCode": "search-prime" }, { "modelCode": "web-reader" }, { "modelCode": "zread" } ] }
] } }
```

The `usageDetails` tool models (`search-prime`, `web-reader`, `zread`) confirm
the `TIME_LIMIT unit 5` entry is the **MCP** quota, not a chat-token window.
This is exactly the lite-plan encoding.

Key excerpts as they exist today:

`ZaiParser.res:10-41` — `zaiWindow` (unit-coded branch gated on `isLitePlan`):

```rescript
let zaiWindow = (
  limitType: string,
  unit: option<float>,
  isLitePlan: bool,
): windowType => {
  let t = limitType->String.toUpperCase
  if isLitePlan {
    if t === "TIME_LIMIT" && unit === Some(5.0) {
      #rollingMcp
    } else if t === "TOKENS_LIMIT" && unit === Some(3.0) {
      #rolling5h
    } else if t === "TOKENS_LIMIT" && unit === Some(6.0) {
      #rollingWeekly
    } else {
      #rolling
    }
  } else {
    if t === "TIME_LIMIT" {
      switch unit {
      | Some(5.0) => #rolling5h
      | Some(u) if u >= 168.0 => #rollingWeekly
      | _ => #rolling
      }
    } else if t === "MCP_LIMIT" {
      #rollingMcp
    } else if t === "TOKENS_LIMIT" {
      #rollingTokens
    } else {
      #rolling
    }
  }
}
```

`ZaiParser.res:133-146` — the title override, also gated on `isLitePlan`
(these literals bypass i18n by design; `baseConcept` comes from
`SemanticLabels.enrichQuotaLabel`):

```rescript
let baseConcept = SemanticLabels.enrichQuotaLabel(providerName, hints)
let concept: SemanticLabels.enrichedLabel = if isLitePlan {
  if type_ === "TIME_LIMIT" && unit === Some(5.0) {
    {label: "MCP quota", concept: SemanticLabels.ZAiMcp}
  } else if type_ === "TOKENS_LIMIT" && unit === Some(3.0) {
    {label: "5h rolling window", concept: SemanticLabels.ZAi5HourRolling}
  } else if type_ === "TOKENS_LIMIT" && unit === Some(6.0) {
    {label: "Weekly quota", concept: SemanticLabels.ZAiWeeklyRolling}
  } else {
    baseConcept
  }
} else {
  baseConcept
}
```

`ZaiParser.res:188-198` — plan detection inside `parseZaiLimits`:

```rescript
// Lite plan encodes MCP / 5h / weekly on different type+unit combinations than
// the full plan (no MCP_LIMIT, no TIME_LIMIT unit=168). Detect via data.level so
// we can map the right human label to each row.
let isLitePlan = switch Dict.get(root, "data") {
| Some(JSON.Object(dataDict)) =>
  switch Dict.get(dataDict, "level") {
  | Some(JSON.String("lite")) => true
  | _ => false
  }
| _ => false
}
```

`ZaiParser.res:199-207` — rows and sort (already yields MCP → 5h → weekly once
windows are assigned; ranks at `:44-51`: `#rollingMcp`=0, `#rolling5h`=1,
`#rollingWeekly`=2, else 3):

```rescript
let entries: array<quotaData> = Belt.Array.keepMap(limits, (entry) => {
  switch entry {
  | JSON.Object(limDict) => limitToQuota(limDict, idPrefix, providerName, isLitePlan)
  | _ => None
  }
})
// Stable sort: rolling-mcp → rolling-5h → rolling-weekly → fallback rows
let _ = entries->Array.sort((a, b) => (zaiSortRank(a.window) - zaiSortRank(b.window) :> float))
```

Label sources for the weekly rename (all four must change together; there is
deliberately NO sync test between `labelMap` and `en.json`):

- `src/i18n/locales/en.json:26` — `"concept.z.ai-weekly-rolling": "Weekly quota",`
- `src/rendering/SemanticLabels.res:45` — `("z.ai-weekly-rolling", "Weekly quota"),`
- `src/Providers/CodingPlanParse/ZaiParser.res:140` — `{label: "Weekly quota", concept: SemanticLabels.ZAiWeeklyRolling}`
- `src/Providers/CodingPlanParseTests.res:605,608` — lite weekly test asserts `Some("Weekly quota")` with message `"Info label should be Weekly quota"`

Note: `"Weekly limit"` already exists as a *value* for other keys
(`minimax-weekly-request`, `openai-secondary-rate`) — duplicate values are
fine; only keys must be unique.

Tests pinning current fallback behavior that MUST be rewritten/kept per this
plan (`src/Providers/CodingPlanParseTests.res`):

- `:747` `test("parseZaiLimits data.level pro yields full-plan labels for TOKENS_LIMIT", ...)` —
  asserts `Some("Token quota #5")` and `#rollingTokens` for
  `level=pro, TOKENS_LIMIT, unit 3, number 5`. **Becomes wrong after the fix.**
- `:780` `test("parseZaiLimits missing level field defaults to full-plan labels", ...)` —
  same fixture without `level`; asserts `Some("Token quota #5")`.
  **Stays correct** (missing level must keep the conservative full-plan default).
- Lite label tests (structure exemplars for new tests): `:500` (TIME_LIMIT u5 →
  `Some("MCP quota")`, `#rollingMcp`), `:540` (TOKENS_LIMIT u3 →
  `Some("5h rolling window")`, `#rolling5h`), `:579` (TOKENS_LIMIT u6 →
  `Some("Weekly quota")`, `#rollingWeekly`).
- Sort test `:678` uses a fixture with **no** `level` field (full-plan path);
  its assertions are unaffected by this plan.

Repo conventions that apply:

- CLAUDE.md: write a ReScript test first for non-trivial changes; all five
  gates must be green (`pnpm test`, `pnpm build`, CLI smoke,
  `bash scripts/check-secrets.sh`, `pnpm codegen` determinism).
- Test assertion style: `assertion(~message=..., (a, b) => a == b, actual, expected)`
  with the custom `test("...", () => {...})` runner — model after the lite
  tests at `CodingPlanParseTests.res:500-610`.
- Never edit `src/Infra/ConfigLoader/Schema.res` or
  `src/i18n/Translator/EnCatalog.res` directly — they are codegen'd
  (`pnpm codegen`) from `schemas/` + `en.json`.
- `legacy/` is archived TypeScript: DO NOT touch.
- Generated `EnCatalog.res` is refreshed from `en.json` by `pnpm codegen`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Install (if needed) | `pnpm install` | exit 0 (postinstall runs codegen) |
| Regenerate assets after `en.json` edit | `pnpm codegen` | exit 0 |
| Codegen determinism | `pnpm codegen --check` | exit 0 |
| Compile + tests | `pnpm test` | all files pass (runner prints per-file results) |
| Full build | `pnpm build` | exit 0, writes `dist/cli/index.js` |
| CLI smoke | `node dist/cli/index.js -p zai` | 3 rows titled MCP quota / 5h rolling window / Weekly limit, in that order |
| Secret gate | `bash scripts/check-secrets.sh` | exit 0 |

## Scope

**In scope** (the only files you should modify):

- `src/Providers/CodingPlanParse/ZaiParser.res`
- `src/Providers/CodingPlanParseTests.res`
- `src/rendering/SemanticLabels.res`
- `src/i18n/locales/en.json`
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though they look related):

- `legacy/**` — archived pre-cutover TypeScript; its copies of
  "Weekly quota" (`legacy/rendering/semantic-labels.ts:38`,
  `legacy/i18n/locales/en.json:26`,
  `legacy/adapters/providers/coding-plan-parse.ts:147`) stay as-is.
- `src/i18n/Translator/EnCatalog.res` — codegen'd; regenerated, never edited.
- The `zaiWindow` unit tests at `CodingPlanParseTests.res:320-413` — they pass
  the flag positionally; renaming the parameter does not affect them.
- The full-plan (`standard`/missing-level) mapping and its tests
  (`:416-473`, `:652-676`, `:678-742`, `:780-804`) — `standard` plans may
  still return `MCP_LIMIT` / `TIME_LIMIT unit>=168` shapes; leave that path
  untouched.
- Any renaming of `"MCP quota"` or `"5h rolling window"` — the operator only
  requested the weekly label change.

## Git workflow

- Work on the current branch; commit per logical unit, conventional commits,
  no AI attribution. Suggested single commit:
  `fix(zai): map pro-plan unit codes to MCP/5h/weekly row labels`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Rename the weekly label to "Weekly limit" (pure rename, stays green)

Change the value in exactly four places:

1. `src/i18n/locales/en.json:26`:
   `"concept.z.ai-weekly-rolling": "Weekly quota",` →
   `"concept.z.ai-weekly-rolling": "Weekly limit",`
2. `src/rendering/SemanticLabels.res:45`:
   `("z.ai-weekly-rolling", "Weekly quota"),` →
   `("z.ai-weekly-rolling", "Weekly limit"),`
3. `src/Providers/CodingPlanParse/ZaiParser.res:140`:
   `{label: "Weekly quota", concept: SemanticLabels.ZAiWeeklyRolling}` →
   `{label: "Weekly limit", concept: SemanticLabels.ZAiWeeklyRolling}`
4. `src/Providers/CodingPlanParseTests.res:605` (message) and `:608`
   (expected): `"Weekly quota"` → `"Weekly limit"` in both.

Then regenerate the catalog:

**Verify**: `pnpm codegen && pnpm codegen --check && pnpm test` → exit 0, all
tests pass (nothing else asserts the old string — verified during planning;
`legacy/` matches don't count, it is not built).

### Step 2: Rewrite the pro regression test and add a pro order test (RED)

In `src/Providers/CodingPlanParseTests.res`:

(a) Replace the test at `:747` (keep the `:744-746` comment block, updating it
to say pro plans ALSO use unit-coded limits; missing `level` still defaults to
full-plan) with:

```rescript
test("parseZaiLimits data.level pro yields unit-coded labels for TOKENS_LIMIT", () => {
```

same fixture (level `"pro"`, `TOKENS_LIMIT`, `unit 3.0`, `number 5.0`,
`usage/currentValue/remaining/percentage` as today), but assertions flipped:

```rescript
assertion(
  ~message="level=pro TOKENS_LIMIT unit 3 should use the 5h rolling label",
  (a, b) => a == b,
  first(result).info,
  Some("5h rolling window"),
)
assertion(
  ~message="level=pro TOKENS_LIMIT unit 3 should map to rolling-5h",
  (a, b) => a == b,
  first(result).window,
  #rolling5h,
)
```

(b) Add ONE new test directly after it, modeling the fixture on the live pro
response (field sets copied from existing green fixtures: TIME_LIMIT from
`:505-514`, TOKENS_LIMIT from `:751-760`, so `computeUsed` returns `Some`):

```rescript
test("parseZaiLimits pro response maps and sorts rows MCP, 5h, Weekly limit", () => {
  let json = JSON.Object(Dict.fromArray([
    ("data", JSON.Object(Dict.fromArray([
      ("level", JSON.String("pro")),
      ("limits", JSON.Array([
        // TOKENS_LIMIT unit 3 → 5h rolling window
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("TOKENS_LIMIT")),
          ("unit", JSON.Number(3.0)),
          ("number", JSON.Number(5.0)),
          ("usage", JSON.Number(100.0)),
          ("currentValue", JSON.Number(1.0)),
          ("remaining", JSON.Number(99.0)),
          ("percentage", JSON.Number(1.0)),
          ("nextResetTime", JSON.Number(1789455747809.0)),
        ])),
        // TOKENS_LIMIT unit 6 → Weekly limit
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("TOKENS_LIMIT")),
          ("unit", JSON.Number(6.0)),
          ("number", JSON.Number(1.0)),
          ("usage", JSON.Number(100.0)),
          ("currentValue", JSON.Number(1.0)),
          ("remaining", JSON.Number(99.0)),
          ("percentage", JSON.Number(1.0)),
          ("nextResetTime", JSON.Number(1790042247981.0)),
        ])),
        // TIME_LIMIT unit 5 → MCP quota
        JSON.Object(Dict.fromArray([
          ("type", JSON.String("TIME_LIMIT")),
          ("unit", JSON.Number(5.0)),
          ("percentage", JSON.Number(0.0)),
          ("nextResetTime", JSON.Number(1792029447999.0)),
        ])),
      ])),
    ]))),
  ]))
  let result = parseZaiLimits(~json, ~idPrefix="zai", ~providerName="z.ai")
  // Sorted: MCP (rank 0) → 5h (rank 1) → weekly (rank 2)
  assertion(
    ~message="row 0 should be the MCP quota window",
    (a, b) => a == b,
    Array.get(result, 0)->Belt.Option.map(r => r.window)->Belt.Option.getExn,
    #rollingMcp,
  )
  assertion(
    ~message="row 0 label should be MCP quota",
    (a, b) => a == b,
    Array.get(result, 0)->Belt.Option.map(r => r.info)->Belt.Option.getExn,
    Some("MCP quota"),
  )
  assertion(
    ~message="row 1 should be the 5h rolling window",
    (a, b) => a == b,
    Array.get(result, 1)->Belt.Option.map(r => r.window)->Belt.Option.getExn,
    #rolling5h,
  )
  assertion(
    ~message="row 1 label should be 5h rolling window",
    (a, b) => a == b,
    Array.get(result, 1)->Belt.Option.map(r => r.info)->Belt.Option.getExn,
    Some("5h rolling window"),
  )
  assertion(
    ~message="row 2 should be the weekly window",
    (a, b) => a == b,
    Array.get(result, 2)->Belt.Option.map(r => r.window)->Belt.Option.getExn,
    #rollingWeekly,
  )
  assertion(
    ~message="row 2 label should be Weekly limit",
    (a, b) => a == b,
    Array.get(result, 2)->Belt.Option.map(r => r.info)->Belt.Option.getExn,
    Some("Weekly limit"),
  )
})
```

(If the file's existing tests use a different accessor idiom for array
positions — see the sort test at `:724-741` — match that idiom instead; the
assertions' substance must not change.)

**Verify**: `pnpm test` → the two pro tests from this step FAIL (that is the
expected RED), and every other test still passes. If unrelated tests fail,
STOP.

### Step 3: Extend the unit-coded mapping to `level: "pro"` (GREEN)

All edits in `src/Providers/CodingPlanParse/ZaiParser.res`:

(a) Rename the flag honestly — it no longer means "lite": in `zaiWindow`
(`:10-14`) and `limitToQuota` (`:87-92`), rename parameter `isLitePlan` →
`usesUnitCodes`, and in `parseZaiLimits` rename the local binding + its single
use site (`:201`). These are positional parameters; external callers (the
unit tests at `:320-413` pass `true`/`false` positionally) are unaffected.

(b) Replace the detection block at `:188-198` with:

```rescript
// lite and pro plans encode MCP / 5h / weekly on different type+unit
// combinations than the full plan (no MCP_LIMIT, no TIME_LIMIT unit=168):
// TIME_LIMIT u5 = MCP, TOKENS_LIMIT u3 = 5h, TOKENS_LIMIT u6 = weekly.
// Unknown or missing levels keep the conservative full-plan mapping.
let usesUnitCodes = switch Dict.get(root, "data") {
| Some(JSON.Object(dataDict)) =>
  switch Dict.get(dataDict, "level") {
  | Some(JSON.String("lite")) => true
  | Some(JSON.String("pro")) => true
  | _ => false
  }
| _ => false
}
```

No changes to `zaiWindow`'s branches, the concept override at `:134-146`
(now labeled "Weekly limit" from Step 1), or the sort.

**Verify**: `pnpm test` → ALL tests pass, including the two from Step 2
(green) and the untouched `:780` missing-level test.

### Step 4: Full gates + smoke

**Verify**, in order:

1. `pnpm codegen --check` → exit 0
2. `pnpm test` → exit 0
3. `pnpm build` → exit 0
4. `bash scripts/check-secrets.sh` → exit 0
5. `node dist/cli/index.js -p zai` → exactly three rows, in order, titles
   `MCP quota`, `5h rolling window`, `Weekly limit` (percentages and reset
   columns vary with live usage; only titles and order are asserted):
   ```text
   | MCP quota         [...] ..% used  ... |
   | 5h rolling window [...] ..% used  ... |
   | Weekly limit      [...] ..% used  ... |
   ```
6. `rg -n "Weekly quota" src/` → no matches (only `legacy/` may still match).
7. `git status` → only in-scope files modified.
8. Update the 009 row in `plans/README.md` to DONE.

## Test plan

Covered by Steps 1-2 (test-first, red in Step 2, green in Step 3):

- Pro + TOKENS_LIMIT unit 3 → `Some("5h rolling window")` + `#rolling5h`
  (rewritten regression test — pins the exact operator-reported bug).
- Full pro response (3 entries, live ordering) → sorted MCP → 5h → weekly
  with correct labels (new end-to-end parser test).
- Lite weekly label now `Some("Weekly limit")` (updated `:579` test).
- Unchanged behaviors that must stay green: lite MCP/5h tests, full-plan
  `standard` tests (`:416-473`, `:652-676`), no-level sort test (`:678`),
  missing-level fallback (`:780`).

Structural pattern: the lite-plan tests at `CodingPlanParseTests.res:500-610`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm test` exits 0; the two new/rewritten pro tests exist and pass
- [ ] `pnpm build` exits 0; `node dist/cli/index.js -p zai` shows the three
      rows titled `MCP quota` / `5h rolling window` / `Weekly limit` in that
      order
- [ ] `pnpm codegen --check` exits 0
- [ ] `bash scripts/check-secrets.sh` exits 0
- [ ] `rg -n "Weekly quota" src/` returns no matches
- [ ] `git status` shows only in-scope files (`ZaiParser.res`,
      `CodingPlanParseTests.res`, `SemanticLabels.res`, `en.json`,
      `plans/README.md`)
- [ ] 009 row in `plans/README.md` updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows any in-scope file changed since `f548fd4`, or the
  "Current state" excerpts don't match the live code.
- Any test OTHER than the two pro tests from Step 2 fails at Step 2, or any
  test still fails after Step 3 (one reasonable fix attempt allowed).
- Evidence emerges that `standard`-level responses ALSO return the
  unit-coded shape (TOKENS_LIMIT u3/u6 without MCP_LIMIT) — that would mean
  the whitelist approach is wrong and the detection should be structural;
  report instead of widening the whitelist.
- The fix appears to require editing anything under `legacy/` or the
  codegen'd `EnCatalog.res` / `Schema.res` files.
- The CLI smoke output shows a fourth z.ai row or different titles than this
  plan's — the live API may have changed again; report the raw JSON
  (redact nothing — response bodies carry no credentials).

## Maintenance notes

- The whitelist at the detection block is the single point to extend when
  z.ai ships another unit-coded level (e.g. `"max"`): add one
  `| Some(JSON.String("max")) => true` arm plus a fixture copied from the
  Step 2 order test.
- If level names keep multiplying, consider structural detection instead
  (e.g. `TIME_LIMIT u5` whose `usageDetails` list tool `modelCode`s → MCP).
  Deliberately deferred: one live sample per level is not enough evidence to
  generalize; the parser currently doesn't even read `usageDetails`.
- `labelMap` (SemanticLabels.res) and `en.json` are duplicated literals kept
  in sync by convention — there is NO sync test (verified 2026-09-14). Any
  future label change must touch both, plus any parser-side literals.
- PR reviewer should scrutinize: the whitelist contains exactly `lite` and
  `pro`; `standard`/missing-level behavior is unchanged; no `legacy/` files
  in the diff.
