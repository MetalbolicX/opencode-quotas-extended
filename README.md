# opencode-quotas-extended

Hexagonal rewrite of the opencode-quotas plugin with SOLID/clean architecture, extended provider list, and strict TDD. Built with **pnpm**, **Node.js**, and **rolldown**.

## Overview

This CLI provides AI provider quota monitoring for the opencode editor. It fetches usage data from 8 providers (OpenAI, opencode Zen, opencode Go, z.ai, Kimi, Minimax, Anthropic, Gemini), renders usage status (OK/WRN/ERR) with progress bars, and aggregates multi-provider data.

## Architecture

```
surfaces → report-pipeline → domain (pure)
                            ↕           ↕
                    port contracts ← adapters (auth/http/providers/render)
```

- **Domain** (`src/domain/`): Pure TypeScript — zero I/O imports. QuotaData types, aggregation strategies, history reset detection.
- **Ports** (`src/ports/`): Interfaces defining the boundaries — `QuotaProvider`, `CredentialSource`, `HistoryStore`, `Renderer`, `Translator`, `HttpClient`, `Logger`.
- **Adapters** (`src/adapters/`): Concrete implementations — 8 provider adapters, auth/json-file sources, fetch HTTP client, config loader.
- **Rendering** (`src/rendering/`): Table, JSON, and Markdown renderers with ANSI status bars.
- **i18n** (`src/i18n/`): Translator port with English locale.
- **CLI** (`src/cli/`): Standalone `opencode-quotas` binary. No opencode plugin dependency.
- **Build**: `rolldown -c` bundles the CLI into a single `dist/cli/index.js` with a `node` shebang.

## Providers

OpenAI · opencode Zen · opencode Go · z.ai · Kimi · Minimax · Anthropic · Gemini

**Production-ready**: OpenAI (OAuth WHAM), z.ai, Minimax (via `mmx` CLI binary).

**Endpoints pending web scraping** (deferred, not implemented): opencode Zen, opencode Go, Kimi. These providers do not publish a public quota API; the maintainers deferred implementation because reliable quota data requires scraping the web console, which falls outside the CLI's contract.

**Endpoints live but credential-blocked**: Anthropic (admin-scope key required), Gemini (Antigravity `antigravity-accounts.json` required). Adapters activate automatically when the credential appears.

## Installation

```bash
pnpm install
pnpm build
```

When published to npm:

```bash
npm install -g opencode-quotas-extended
opencode-quotas --help
```

## Configuration

Place `.opencode/quotas.json` in the directory where you run the CLI (config is resolved from `process.cwd()`). See `schemas/quotas.schema.json` for the full schema.

Credentials are resolved in order: `auth.json` (XDG data dir) → environment variables → `quotas.json` credential override.

## CLI

```bash
opencode-quotas                        # Full table report
opencode-quotas --list               # List available providers
opencode-quotas --provider openai     # Single provider report
opencode-quotas --provider openai --color green  # With colored usage bar
opencode-quotas --mode json           # JSON output
opencode-quotas --mode markdown       # Markdown table
opencode-quotas --help                # Show usage
```

Run directly from the build output (no global install needed):

```bash
pnpm build                              # Rolldown bundle → dist/cli/index.js
./dist/cli/index.js --list              # Shebang: #!/usr/bin/env node
```

Or after `npm install -g`: `opencode-quotas --list`.

## Development

```bash
pnpm test               # Run all tests (vitest)
pnpm test:watch         # Watch mode
pnpm test:coverage      # Coverage report
pnpm typecheck          # TypeScript type checking
pnpm build              # Bundle with rolldown → dist/cli/index.js
bash scripts/check-secrets.sh  # Secret-leak gate
```

## Design Principles

- **Zero secrets in source**: `scripts/check-secrets.sh` rejects `GOCSPX`, `client_secret`, `sk-`, and `Bearer` patterns in `src/`, `scripts/`, and `schemas/`. `auth.json` and `antigravity-accounts.json` are gitignored.
- **Immutable domain**: `QuotaData` is a plain readonly object; no mutable state in the core. `predictedReset` was removed because prediction is not wired in this release (the prediction module exists for future use).
- **Failure isolation**: Each provider adapter runs independently. HTTP/network failures reject so the pipeline records them in its per-provider error map and the CLI exits non-zero or marks the partial result, instead of silently returning empty data.
- **TDD-first**: Every behavior is driven by a failing test before implementation.

## Status

Gates (run locally; CI is intentionally not part of this repository):

| Gate | Result |
|------|--------|
| `pnpm test` | ✅ 641 tests pass |
| `pnpm typecheck` | ✅ 0 errors |
| `bash scripts/check-secrets.sh` | ✅ exit 0 |
| `pnpm build` | ✅ `dist/cli/index.js` produced |
| `node dist/cli/index.js --help` | ✅ works under plain Node |

**8 providers**: OpenAI · opencode Zen · opencode Go · z.ai · Kimi · Minimax · Anthropic · Gemini.
Three (Zen, Go, Kimi) are deferred because they would require web scraping. Two (Anthropic, Gemini) are live-but-credential-blocked. Three (OpenAI, z.ai, Minimax) are production-ready.

## Open issues / Caveats

This release closes the following implementation gaps (see CHANGELOG):
- Anthropic admin-usage endpoint (was TODO(research)): now implemented as a mock-only defensive parser with documented-shape fixture (validation-pending until admin-scope credential is available). Requires an Anthropic admin key with `usage:read` scope plus an `orgId`. `orgId` resolution priority: `config` → `auth.json` → `env ANTHROPIC_ORG_ID`.
- Gemini Antigravity quota endpoint (was TODO(research)): now implemented via Google's Cloud Code Antigravity API (`fetchAvailableModels`). Reads OAuth refresh_token from `~/.config/opencode/antigravity-accounts.json` (array of `{email, refreshToken, projectId|managedProjectId}`), fallback to `auth.json.gemini`. Per-model rows with `remainingFraction`.
- OpenAI `/v1/usage` pagination (was TODO(research)): now implemented as a mock-only cursor-based pagination loop (cap 20) on the raw-key platform path. OAuth WHAM path is unchanged.
- `info` / `window` strict-union invariant: all 8 providers now populate these per-entry; `window` is never a free-form string at the domain boundary.
- Type-safety cleanup: `QuotaProvider.fetchQuotas()` is zero-arg on the port; `modelId?: string` lives on `QuotaData`.
- Performance: i18n translator hoisted to module scope; aggregation uses `Map`-based lookup; history store caches parsed JSON.

### Remaining caveats (live capture pending)
- Anthropic admin-scope credential is not present in `auth.json`; the adapter activates automatically when added. See `notes/anthropic-admin-scope-blocked.md`.
- OpenAI raw-key `OPENAI_API_KEY` is not present (only OAuth); the pagination path activates automatically when added. See `notes/openai-raw-key-blocked.md`.
- Antigravity credential file is not present; the Gemini adapter activates automatically when `~/.config/opencode/antigravity-accounts.json` (or `auth.json.gemini`) appears.
- Prediction/ETTL wiring: the prediction module exists in `src/domain/prediction.ts` (dual-window linear regression) but is not connected to the pipeline. The default aggregation strategy is `max` until prediction is wired in a future release.
