# list-redesign — T3 S5 functional-check evidence

Scope: functional-check execution for T3 (covers S1, S2, S3, S4, S5 interactions).
This is NOT an independent verifier run (that gap is accepted by the user, L8 in
`odd/tasks/list-redesign.md`). No production source, test, or generated artifact was
modified; nothing was staged/committed. The current tree's `dist/cli/index.js` was used
as the "current" bundle; the scratch base was built only in the scratch copy.

## Artifacts under test

- Current bundle: `dist/cli/index.js` sha256 `602b8cfbcf8cf9514a52d4c2870ba8fcd68ae4112fe93a4e4933176533f0e1ec` (135080 bytes), built from working tree at HEAD `9c6052188c9b4741689e0e7ed65b2bc6199753a8` (T1) + uncommitted T2.
- Scratch base: git archive `37238ef404b4cd6682cfad25757e3a474928ea20` (spec baseline) under `/tmp/list-redesign-t3-kpaAJd/base`; built with `pnpm build` → `base/dist/cli/index.js` sha256 `e534ede9654928d9bffa2ac415e8d18639706b0b6551bba0f32a68234824ed49` (134864 bytes), build exit 0 (2.1s).
- Runtime: node `v24.21.0` (absolute path used for every child).

## Method

Scratch setup (in task TMPDIR, never in the repo):

```
TMPDIR=$(mktemp -d /tmp/list-redesign-t3-XXXXXX)     # -> /tmp/list-redesign-t3-kpaAJd
git archive 37238ef… | tar -x -C "$TMPDIR/base"
ln -s <repo>/node_modules "$TMPDIR/base/node_modules"
cd "$TMPDIR/base" && pnpm build
```

Per case, a fresh run dir `mktemp -d` under TMPDIR holds `opencode/`, `pi/`, `claude/`,
`bin/`. The child is launched as:

```
cd "$rundir" && env -i HOME="$rundir" XDG_DATA_HOME="$rundir" \
  PI_CODING_AGENT_DIR="$rundir/pi" CLAUDE_CONFIG_DIR="$rundir/claude" \
  PATH="$rundir/bin" "$NODE_ABS" "$CLI" <args...>
```

`env -i` clears every inherited variable, so no provider API key can leak in (the task
required this). `PATH` contains only the controlled `bin/`. For the fake‑`mmx` cases the
`bin/` holds a fake `mmx` (fixture from `src/Providers/MinimaxTests.res`) plus a minimal
`which` shim that resolves only against the controlled `PATH` — without it `which mmx`
cannot resolve in an otherwise-empty PATH, so the probe would always report
unavailable. This shim is test scaffolding, not production behavior. No live provider
was contacted and no real credential file was read (all fixtures are inside the run dir).

Auth fixtures: `none` (no `auth.json`), `empty` (`{}` valid empty opencode auth.json),
`two` (`openai` + `zai-coding-plan` API-key entries). Before/after every run the
`opencode/auth.json` sha256 and the set of files under the run dir were recorded.

## Part A — provider commands, no credentials (S5 preserved)

`-p <id> -m <table|json|markdown> -c green` for all 7 registered providers
(openai, go, zai, kimi, minimax, anthropic, gemini), auth=`empty`, PATH empty.
42 runs (21 base + 21 current).

Result: pairs=21, raw_stdout_diffs=0, raw_stderr_diffs=21, raw_exit_diffs=0,
normalized_equal=21, all exits=1.

Every raw stderr diff is the single approved registry-line change:

```
base:  Available: openai, zen, go, zai, kimi, minimax, anthropic, gemini
current: Available: openai, go, zai, kimi, minimax, anthropic, gemini
```

Normalization applied was exactly `s/, zen//g` on that diagnostic line only. After it,
all 21 pairs are byte-identical. The `-m` and `-c` flags do not change the early-exit
diagnostic, so all 3 modes reduce to the same message.

## Part B — fake authenticated `mmx`, Minimax availability differential (S2/S5)

`-p minimax -m <table|json|markdown>`, auth=`empty`, PATH = controlled bin with fake
`mmx` (fixture `model_remains` general 90%/80%, remains 9600000/214848000). 6 runs.

Result: base exit 0, current exit 0 (both treat the authenticated session as
available — no "No credentials" path). stderr identical and empty.

- table: STDOUT IDENTICAL (base == current)
- markdown: STDOUT IDENTICAL
- json: 3 lines differ:
  `"fetchedAt"` and the two `"reset"` epoch-millis strings (base run ~170ms before
  current). This is `Date.now()`-derived, an expected time-dependent difference, not a
  behavior change. After normalizing 13-digit epoch millis to `<EPOCH>` the JSON is
  byte-identical.

This covers the `mmxSessionAvailable` refactor in `src/Providers/Minimax.res`: the
`-p minimax` fetch/availability path is unchanged vs base. The provider flow wrote
`opencode/quota-history.json` in both (existing durable-history behavior); `auth.json`
sha256 unchanged.

## Part C — `-l -p <id>` usage error (S5)

`-l -p openai`, auth=`empty`. base exit 2, current exit 2. stderr diff is exactly the
two intentionally changed usage lines:

```
  -l, --list            Show available providers as a numbered list …   (base)
  -l, --list            Show available subscriptions and credential source … (current)
  -m, --mode <mode>     Output format: table (default), json, markdown  (base)
  -m, --mode <mode>     Output format for list and usage: …             (current)
```

No other line differs.

## Part D — `--help` (S5)

`--help`, auth=`none`. base exit 0, current exit 0. stdout diff is exactly the same two
approved lines (`-l` and `-m` descriptions). stdout bytes base=592, current=618. No
other line differs.

## Part E — list error contracts (S5)

- `-l` with no `auth.json`: base exit 1, current exit 1. stderr identical after
  replacing the run-dir path with `<RUN>` (only `Checked: <RUN>/opencode/auth.json`
  contains the temp path). Message unchanged.
- no flags with no `auth.json`: identical (exit 1), same message.
- `-l` with `{}` (no usable credential): base and current both exit 1 with identical
  stdout (empty) and identical stderr "No subscriptions with credentials found. …".

## Part F — current `-l` exact output, two-provider auth (S1/S2/S3)

`-l -m table`, `-l -m markdown`, `-l -m json`, and no-flags, auth=`two`
(`openai` + `zai-coding-plan`), PATH empty. All exit 0, stderr empty, no history file
created.

table and markdown are byte-identical and match `src/integration/E2eSmokeTests.res`
expected output exactly (286 bytes, single trailing newline):

```
## Available subscriptions (2)

| # | ID     | Provider         | Credential |
|--:|--------|------------------|------------|
| 1 | openai | OpenAI           | opencode   |
| 2 | zai    | z.ai Coding Plan | opencode   |

Run `opencode-quotas -p <id>` to see usage for one subscription.
```

json matches the E2eSmokeTests expected array exactly, with no Markdown header/footer:

```
[
  {
    "id": "openai",
    "name": "OpenAI",
    "credential": "opencode"
  },
  {
    "id": "zai",
    "name": "z.ai Coding Plan",
    "credential": "opencode"
  }
]
```

No-flags output equals the table output. Base `-l` (old numbered list) is different by
design (S1).

## Part G — read-only list credentials / no stored-state mutation

Across all 69 recorded runs, the `opencode/auth.json` sha256 was identical before and
after: `CHANGED` count = 0. In list mode the only file present after the run is
`./opencode/auth.json` — no `quota-history.json`, no counters. The only case that
created `quota-history.json` is the `-p minimax` provider flow (Part B), which is the
pre-existing durable-history behavior, identical in base and current.

## S4 — removed provider interaction

`-p zen` (current) → exit 1, stderr
`No credentials found for 'zen'.` + registry line without zen. Base behaved the same
apart from the approved `, zen` registry difference. `-p zen` never reached a Zen
adapter in current (unknown provider path). The 7 registered providers are exactly
those exercised in Part A.

## Unexpected / unrequested differences

None. Every difference observed is one of: the approved Zen registry removal
(`-p <id>` diagnostics and `-p zen`), the two approved help/usage text lines, the
`Date.now()` epoch fields in minimax JSON output, or the run-dir path in the
missing-auth message (identical text).

## Commands and statuses (summary)

| Check | Command shape | base exit | current exit | verdict |
|---|---|---|---|---|
| A (21 pairs) | `-p <7 ids> -m table,json,markdown -c green` | 1 | 1 | identical after `, zen` normalize |
| B table | `-p minimax -m table` + fake mmx | 0 | 0 | byte-identical |
| B markdown | `-p minimax -m markdown` + fake mmx | 0 | 0 | byte-identical |
| B json | `-p minimax -m json` + fake mmx | 0 | 0 | identical after epoch normalize |
| C | `-l -p openai` | 2 | 2 | 2 approved help lines only |
| D | `--help` | 0 | 0 | 2 approved help lines only |
| E | `-l` (auth none) | 1 | 1 | identical after `<RUN>` normalize |
| E2 | no flags (auth none) | 1 | 1 | identical |
| E3 | `-l` (auth `{}`) | 1 | 1 | identical |
| F | `-l [-m table/json/markdown]` (auth two) | — | 0 | matches E2eSmokeTests exactly |
| S4 | `-p zen` | 1 | 1 | unknown-provider error (+ approved `, zen`) |

No command timed out; every command was finite and completed in the foreground.

## Coverage / blockers

Covered: S1 (list table/json/markdown exact), S2 (credential labels via two-provider
`-l`; mmx session fallback via fake `mmx`; read-only list), S3 (json shape), S4 (zen
removal in `-p`/registry diagnostics), S5 (help/missing-auth/no-subscriptions/usage
error/provider no-credential/fetch behavior preserved).

Blockers / limitations:
1. The controlled fake-mmx environment needs a `which` shim because `PATH` is otherwise
   empty; without it the mmx probe can never resolve. Recorded above, not a product issue.
2. Minimax JSON contains `Date.now()`-derived epoch fields; byte-identity there is not
   achievable across two invocations, so it was verified after epoch normalization.
3. The scratch scratch dir's `node_modules` symlink was materialized into a real
   directory by `pnpm build` (from the local pnpm store, offline). The repo's own
   `node_modules` and working tree were not modified (`git status` count unchanged at 23).
