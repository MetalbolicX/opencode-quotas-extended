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
- **Plugin** (`src/plugin/`): opencode plugin hook that appends a quota footer to assistant responses.
- **CLI** (`src/cli/`): Standalone `opencode-quotas` binary.

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

- `/quotas` — Render the full quota report in your opencode session. Calls the same pipeline as the CLI.
- **Footer hook**: After each assistant response, a compact quota status bar is appended automatically.

## CLI

```bash
opencode-quotas                        # Full table report
opencode-quotas --mode json            # JSON output
opencode-quotas --mode markdown        # Markdown table
opencode-quotas --provider openai       # Single provider
opencode-quotas --no-color             # Strip ANSI codes
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
bun run test         # Run all tests (280 passing)
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

**10/10 slices complete.** All gates pass:

| Gate | Result |
|------|--------|
| `bun run test` | ✅ 280 tests pass |
| `bun run typecheck` | ✅ 0 errors |
| `bash scripts/check-secrets.sh` | ✅ exit 0 |
| `bun run build` | ✅ dist/ produced |

**8 providers**: OpenAI · opencode Zen · opencode Go · z.ai · Kimi · Minimax · Anthropic · Gemini.
Five (Zen, Go, z.ai, Kimi, Minimax) have `TODO(research)` endpoints pending URL pinning before production use.

Run `bun run test` to execute all gates. See [Open Issues](#open-issues) for the pending endpoint list.

## Open Issues

The following endpoints are not yet pinned and require research before production use:

| Provider | Issue | Details |
|---|---|---|
| OpenAI | Confirm exact WHAM URL | `TODO(research)` in `src/adapters/providers/openai.ts` |
| opencode Zen | Pin billing endpoint | `TODO(research): https://opencode.ai/api/billing/...` |
| opencode Go | Pin billing endpoint | `TODO(research): https://opencode.ai/api/billing/...` |
| z.ai | Pin usage endpoint | `TODO(research): https://api.z.ai/api/.../usage` |
| Kimi | Pin usage endpoint | `TODO(research): https://platform.moonshot.ai/api/.../usage` |
| Minimax | Pin usage endpoint | `TODO(research): https://platform.minimax.io/api/.../usage` |
| Anthropic | Pin org-scoped URL | `TODO(research): https://api.anthropic.com/v1/organizations/{org_id}/usage` |
| Gemini | Pin quota endpoint | `TODO(research): https://generativelanguage.googleapis.com/v1beta/...` |

These are stub adapters with `TODO(research)` URL placeholders. Live billing integration for coding-plan providers will be completed once endpoints are confirmed.
