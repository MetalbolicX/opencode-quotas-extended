# Subscription list redesign
Approved plan: remove Zen entirely, then render credential-aware subscription lists.
Branch: feat/subscription-list. Baseline: 37238ef. No push, PR, or merge authorized.

## Specs
S1. User: "I want you to redesign the -l flag to show the available subscriptions." Approved output: `## Available subscriptions (N)`, blank line, padded Markdown table with columns `#`, `ID`, `Provider`, `Credential`; blank line then `Run ` + backtick + `opencode-quotas -p <id>` + backtick + ` to see usage for one subscription.` Numbers right-aligned, registry order, available providers only. Each cell has one outside space; separator width is content width + 2, first separator ends in colon. Table and markdown modes are identical.
S2. User: "1. Keep it." Keep Credential column: opencode, pi, claude-code, env, config, mmx. Show the first locally selected source, not a remotely validated credential. Preserve provider-specific resolution keys and Minimax session fallback; no quota fetch or token writes in list mode.
S3. User: "3. It is OK." Honor `-l -m json`: 2-space-indented array of objects with only id, name, credential, followed by newline; no Markdown header/footer.
S4. User: "Remove the provider entirely (recommended)". Remove Zen registration, adapter, Zen-only parser/exports/tests, default opencode-zen-monthly group, zen auth mappings, script and docs references. Keep Go's `/zen/go/v1/usage` endpoint unchanged. Keep unrelated fixture strings and shared parser helpers. Seven registered providers and four default groups remain. `-p zen` uses the existing unknown-provider error, exit 1.
S5. Preserve missing auth.json, no subscriptions, invalid list/provider combination and provider quota behavior. CLI tests isolate XDG_DATA_HOME, PI_CODING_AGENT_DIR, CLAUDE_CONFIG_DIR under os.tmpdir(), restore environment and clean up. Assert exit code and exact stdout/stderr; never access real credentials in tests. Update help, README and CLAUDE.md for changed behavior. User: "You can execute".

## Tasks
- T1 [S4,S5] in_progress | route: bounded worker then parent docs/checks | commit: pending | Remove Zen, pin registry/groups/CLI errors, preserve shared parsers. Risk: item 3 (requested provider/exports removal).
- T2 [S1,S2,S3,S5] pending | route: inline or bounded worker after T1 | commit: pending | Add source reporting, pure list renderer, CLI wiring, isolated exact-output tests and docs. Risk: item 3 (shared provider port).
- T3 [S1-S5] pending | route: parent + independent verify | commit: pending | All gates, isolated differential checks, native review if due, final evidence. Risk: item 3.

## Log
L1. Original request: "I want you to redesign the -l flag to show the available subscriptions. The current one looked good when there are a few. Now, with many it looks awful. Check the output and you me an output to implement a new one. Maybe format like markdown"
L2. User: "1. Keep it. 2. lets remove it because it is an pre payment dollar to use different models, but it doesn't show any bar of usage. 3. It is OK. Create the actionable steps to make this change. Do not implement"
L3. User selected: "Remove the provider entirely (recommended)" (remove-provider).
L4. User: "You can execute". Approved prior two-unit implementation plan. Forecast ~800 authored changed lines (including deleted Zen parser/tests); separate reviewable commits, no PR creation. One cohesive deletion unit may exceed 400 lines due to removing obsolete parser tests; no artificial code compression/slicing.
L5. Baseline pnpm test: 59 files passed; pnpm build: exit 0. Implementation will use focused RED/GREEN checks, then full gates and an independent verifier for named item 3.
L6. T1 worker observed RED registry/groups/key/invariant tests (exit 1), GREEN registry 9, groups 7, keys 5, invariant 8, parser 49, architecture 4, CLI removal 1 tests (exit 0). Parent spot check registry 9/9 passed. Deleted-source compiled artifacts were orphaned by ReScript; removed by worker. README/CLAUDE and interface comments updated. Rollback: restore Zen provider/registration/parser/group/mappings and tests together; no stored data changed.
