# CLAUDE.md — opencode-quotas-extended

> Agent context file. Read before making changes. Linked from `AGENTS.md`-style conventions.

## What this project is

Standalone TypeScript CLI (`opencode-quotas`) that fetches AI provider quota usage and renders a status report. Hexagonal architecture with pure domain + port-based adapters.

## Stack

- **Package manager**: pnpm (no Bun in the repo; deprecated)
- **Runtime**: Node 18+ (target 24.x for dev)
- **Transpiler/Bundler**: rolldown (`rolldown -c`) — produces single-file ESM bundle at `dist/cli/index.js`
- **Type check**: `tsc --noEmit`
- **Tests**: vitest
- **Schema validation**: ajv + ajv-formats (bundled externally, resolved at runtime via `dependencies`)

## Build / verify commands

```bash
pnpm install         # Install
pnpm test            # Run all 641 tests
pnpm typecheck       # tsc --noEmit
pnpm build           # rolldown bundle → dist/cli/index.js (Node shebang)
node dist/cli/index.js --help   # Smoke test
bash scripts/check-secrets.sh   # Secret-leak gate
```

All four gates must be green before considering a change done.

## Directory layout

```
src/
  domain/        # Pure logic — zero I/O, zero Node imports
    types.ts             # QuotaData, HistoryPoint
    aggregation.ts       # max/min/mean/median/most_critical
    aggregation-defaults.ts  # 5 default groups
    prediction.ts        # ETTL module (not wired yet)
    reset.ts             # History reset detection
  ports/         # Interfaces only
    provider.ts          # QuotaProvider (fetchQuotas(): Promise<QuotaData[]>)
    credentials.ts       # CredentialSource
    http.ts              # HttpClient, FetchContext
    history.ts           # HistoryStore
    renderer.ts          # Renderer, RenderContext
    translator.ts, logger.ts
  adapters/      # Concrete impls of ports
    providers/           # openai, zen, go, zai, kimi, minimax, anthropic, gemini
    auth/                # credential-resolver, auth-json-source, env-source, config-source, redactor, provider-keys
    infra/               # config-loader, fetch-http, json-file-history, paths
  rendering/     # Table/JSON/Markdown renderers, colors, semantic-labels, status-bar
  i18n/          # Translator + locales/en.json (statically imported, bundled)
  application/   # report-pipeline.ts (the only orchestrator)
  cli/           # CLI entry (src/cli/index.ts)
schemas/         # quotas.schema.json (statically imported by config-loader)
tests/           # Vitest — unit (mirrors src/), integration, architecture, characterization
```

## Core invariants

- **Domain is pure**: `src/domain/**` must have ZERO I/O or Node built-in imports. Verified by `tests/architecture/domain-purity.test.ts`.
- **Ports are interfaces**: adapters satisfy them; domain depends only on ports, never on adapters.
- **Provider failures reject**: adapter `fetchQuotas()` throws on HTTP/network failures — the pipeline records them in `result.errors`. Only "no credential" resolves to `[]`.
- **`QuotaData`**: `{ id, providerName, used, limit, unit, reset, window, info?, modelId? }`. There is NO `predictedReset` field (removed when prediction was unwired).
- **Aggregation default strategy**: `max`. `most_critical` is implemented but requires ETTL history wiring before use.
- **Config resolution**: `.opencode/quotas.json` from `process.cwd()` (not the bundle location).
- **Schema import**: `schemas/quotas.schema.json` is a static `import` (works under rolldown bundling).

## Provider status

| Provider | Status |
|---|---|
| OpenAI (OAuth) | ✅ Production |
| z.ai | ✅ Production |
| Minimax (mmx CLI) | ✅ Production |
| opencode Zen | ⚠️ Needs web scraping (deferred) |
| opencode Go | ⚠️ Needs web scraping (deferred) |
| Kimi | ⚠️ Needs web scraping (deferred) |
| Anthropic | 🔒 Live, requires admin-scope key |
| Gemini | 🔒 Live, requires Antigravity credentials |

## What agents should know

- The repo runs on plain Node, not Bun. Don't add `Bun.*` APIs.
- Don't add a CI workflow unless explicitly asked — user opted out of CI in this repo.
- Don't add a lint/format tool (no eslint/biome) unless asked — keep the toolchain lean.
- The `bun.lock` is gone; use `pnpm-lock.yaml`.
- Translation (`y.*/z.ai` rows, `en.json` labels) was deliberately aligned in earlier sessions; tests in `tests/unit/providers/{minimax,zai}.test.ts` assert the shipped labels.
- When making a non-trivial change, write a test first (TDD). The architecture test suite enforces domain purity, scaffold structure, build-script invariants, and vitest thresholds.

## When picking up a task

1. Read the recent git log: `git log --oneline -20`.
2. Skim `tests/architecture/*` to understand what's enforced.
3. Run `pnpm test` first to confirm a green baseline.
4. Make the change, run the four gates.
5. Update README and this file if behavior or commands change.
