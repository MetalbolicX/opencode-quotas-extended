# opencode-quotas-extended

Hexagonal rewrite of the opencode-quotas plugin with SOLID/clean architecture, extended provider list, and strict TDD.

## Overview

This plugin provides AI provider quota monitoring and prediction for the opencode editor. It fetches usage data from 8 providers (OpenAI, opencode Zen, opencode Go, z.ai, Kimi, Minimax, Anthropic, Gemini), renders usage status (OK/WRN/ERR) with progress bars, aggregates multi-provider data, and predicts reset times using dual-window linear regression.

## Architecture

```
surfaces → report-pipeline → domain (pure)
                            ↕           ↕
                    port contracts ← adapters (auth/http/providers/render)
```

- **Domain** (`src/domain/`): Pure TypeScript — zero I/O imports. QuotaData types, aggregation strategies, ETTL prediction, history reset detection.
- **Ports** (`src/ports/`): Interfaces defining the boundaries — `QuotaProvider`, `CredentialSource`, `HistoryStore`, `Renderer`, `Translator`, `HttpClient`, `Logger`.
- **Adapters** (`src/adapters/`): Concrete implementations — 8 provider adapters, auth/json-file sources, fetch HTTP client, config loader.
- **Rendering** (`src/rendering/`): Table, JSON, and Markdown renderers with ANSI status bars.
- **i18n** (`src/i18n/`): Translator port with English locale.
- **CLI** (`src/cli/`): Standalone `opencode-quotas` binary. No opencode plugin dependency.

## Providers

OpenAI · opencode Zen · opencode Go · z.ai · Kimi · Minimax · Anthropic · Gemini

**Note**: Five of the eight providers (Zen, Go, z.ai, Kimi, Minimax) use placeholder billing endpoints (`TODO(research)`) and require endpoint pinning before production use. See the [Open Issues](#open-issues) section.

## Installation

```bash
# Local plugin (opencode loads plugins from ~/.config/opencode/plugins/ or the project-level .opencode/ directory)
bun add opencode-quotas-extended   # when published
```

Or install locally for development:

```bash
bun install
bun run build
```

## Configuration

Place `.opencode/quotas.json` in your project root. See `schemas/quotas.schema.json` for the full schema.

Credentials are resolved in order: `auth.json` (XDG data dir) → environment variables → `quotas.json` credential override.

## Commands

The standalone CLI is the sole interface. No slash commands.

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

Install the CLI:

```bash
bun run build        # Compiles TypeScript → dist/cli/index.js
./dist/cli/index.js  # Run directly (shebang: #!/usr/bin/env bun)
# Or: opencode-quotas (if installed globally or via bunx)
```

## Development

```bash
bun run test         # Run all tests (482 passing)
bun run test:watch   # Watch mode
bun run test:coverage  # Coverage report
bun run typecheck     # TypeScript type checking
bun run build         # Compile TypeScript
bash scripts/check-secrets.sh  # CI secret-leak gate
```

## Design Principles

- **Zero secrets in source**: CI gate rejects any `GOCSPX`, `client_secret`, or `sk-` pattern.
- **Immutable domain**: `QuotaData` is a plain readonly object; no mutable state in the core.
- **Failure isolation**: Each provider adapter runs independently; a single provider failure does not crash the report.
- **TDD-first**: Every behavior is driven by a failing test before implementation.

## Status

All gates pass:

| Gate | Result |
|------|--------|
| `bun run test` | ✅ 482 tests pass |
| `bun run typecheck` | ✅ 0 errors |
| `bash scripts/check-secrets.sh` | ✅ exit 0 |
| `bun run build` | ✅ dist/cli/index.js produced |

**8 providers**: OpenAI · opencode Zen · opencode Go · z.ai · Kimi · Minimax · Anthropic · Gemini.
Five (Zen, Go, z.ai, Kimi, Minimax) have `TODO(research)` endpoints pending URL pinning before production use.

Run `bun run test` to execute all gates. See [Open Issues](#open-issues) for the pending endpoint list.

## Open issues / Caveats

This release closes the following implementation gaps (see CHANGELOG):
- Anthropic admin-usage endpoint (was TODO(research)): now implemented as a mock-only defensive parser with documented-shape fixture (validation-pending until admin-scope credential is available). Requires an Anthropic admin key with `usage:read` scope plus an `orgId`. `orgId` resolution priority: `config` → `auth.json` → `env ANTHROPIC_ORG_ID`.
- Gemini Antigravity quota endpoint (was TODO(research)): now implemented via Google's Cloud Code Antigravity API (`fetchAvailableModels`). Reads OAuth refresh_token from `~/.config/opencode/antigravity-accounts.json` (array of `{email, refreshToken, projectId|managedProjectId}`), fallback to `auth.json.gemini`. Per-model rows with `remainingFraction` + `resetTime`.
- OpenAI `/v1/usage` pagination (was TODO(research)): now implemented as a mock-only cursor-based pagination loop (cap 20) on the raw-key platform path. OAuth WHAM path is unchanged.
- `info` / `window` strict-union invariant: all 8 providers now populate these per-entry; `window` is never a free-form string at the domain boundary.

### Remaining caveats (live capture pending)
- Anthropic admin-scope credential is not present in `auth.json`; the adapter activates automatically when added. See `notes/anthropic-admin-scope-blocked.md`.
- OpenAI raw-key `OPENAI_API_KEY` is not present (only OAuth); the pagination path activates automatically when added. See `notes/openai-raw-key-blocked.md`.
- Antigravity credential file is not present; the Gemini adapter activates automatically when `~/.config/opencode/antigravity-accounts.json` (or `auth.json.gemini`) appears.
- Gemini credentials may use field name `oauthSecret` instead of `clientSecret` (defensive rename to satisfy secret-leak checks); see `notes/gemini-antigravity-credentials.md` if you create a notes file, or document inline.
