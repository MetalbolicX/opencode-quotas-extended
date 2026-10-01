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

- [ ] T1. SemanticLabels: add Go5hRolling/GoWeekly/GoMonthly variants + concept strings (go-5h-rolling, go-weekly, go-monthly); mirror .resi.
- [ ] T2. en.json: add concept.go-5h-rolling / concept.go-weekly / concept.go-monthly; pnpm codegen to regenerate EnCatalog.
- [ ] T3. GoParser: window→concept mapping, render via buildProviderName; update GoParserTests expectations.
- [ ] T4. All five gates green; close out.

## Evidence log

(commit identities appended per task)
