# Feature: opencode Go row names — z.ai parity

> ODD feature document. Created before the first source write.

## Goal

Rename opencode Go usage rows from the plain "Go 5h" / "Go Weekly" / "Go Monthly"
format to the z.ai treatment: brand + `·` + i18n concept label.

## Decision (user-approved)

Option A — full parity. Rows become:

- `Go · 5h rolling window`
- `Go · Weekly limit`
- `Go · Monthly quota`

Brand stays short `Go` (z.ai also uses short `z.ai` in rows). Ids (`go-*`),
credential key (`opencode-go`), filter id (`go`), and README unchanged.

## Research evidence (pre-implementation)

- Today: `src/Providers/CodingPlanParse/GoParser.res:31` hardcodes `info = \`${providerName} ${label}\`` with labels 5h/Weekly/Monthly.
- z.ai: `ZaiParser` → `SemanticLabels.buildProviderName("z.ai", concept)`; labels come from `concept.z.ai-*` keys in `src/i18n/locales/en.json` (labels: "5h rolling window", "Weekly limit", "MCP quota").
- Locked tests: `GoParserTests.res` asserts "Go 5h", "Go Weekly", "Go Monthly" (4 assertions).

## Tasks

- [x] T1. SemanticLabels (d310bef): add Go5hRolling/GoWeekly/GoMonthly variants + concept strings (go-5h-rolling, go-weekly, go-monthly); mirror .resi.
- [x] T2. en.json (d310bef): add concept.go-5h-rolling / concept.go-weekly / concept.go-monthly; pnpm codegen to regenerate EnCatalog.
- [x] T3. GoParser (d310bef): window→concept mapping, render via buildProviderName; update GoParserTests expectations.
- [x] T4. All five gates green; close out.

## Evidence log

(commit identities appended per task)

## Evidence log

| Commit | Scope |
|---|---|
| d310bef | feat(providers): Go concepts + conceptKey extraction + branded GoParser rows + tests |

All five gates green (codegen --check, 55 test files, build, smoke, secrets).
Rendered rows verified: "Go · 5h rolling window" / "Go · Weekly limit" / "Go · Monthly quota".
