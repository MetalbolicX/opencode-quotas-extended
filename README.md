# opencode-quotas-extended

ReScript-based CLI that fetches AI provider quota usage and renders a status report. Hexagonal architecture with pure domain + port-based adapters. Built with **pnpm**, **Node.js**, **ReScript**, and **rolldown**.

## Overview

This CLI provides AI provider quota monitoring for the opencode editor. It fetches usage data from 8 providers (OpenAI, opencode Zen, opencode Go, z.ai, Kimi, Minimax, Anthropic, Gemini), renders usage status (OK/WRN/ERR) with progress bars, and aggregates multi-provider data.

## Architecture

```
sources → Bootstrap.res (CLI entry)
              ↓
         Cli.res → ReportPipeline.res
              ↓
         domain (pure ReScript) ←→ ports (interfaces)
              ↓                         ↓
         adapters (infra/providers/auth)  ←  external I/O
```

- **Domain** (`src/domain/`): Pure ReScript — zero I/O imports. `QuotaData` types, aggregation strategies, history reset detection.
- **Ports** (`src/ports/`): Interface definitions — `QuotaProvider`, `CredentialSource`, `HistoryStore`, `Renderer`, `Translator`, `HttpClient`, `Logger`.
- **Adapters** (`src/Providers/`, `src/Auth/`, `src/Infra/`): Concrete implementations — 8 provider adapters, auth sources, HTTP client, config loader.
- **Rendering** (`src/rendering/`): Table, JSON, and Markdown renderers with ANSI status bars.
- **i18n** (`src/i18n/`): Translator with English locale (generated from `src/i18n/locales/en.json`).
- **CLI** (`src/Cli/`): `Bootstrap.res` — rolldown bundles the compiled `lib/es6/src/Cli/Bootstrap.res.mjs` into `dist/cli/index.js`.
- **Build chain**: `pnpm codegen` (generate schema/catalog `.res` modules) → `pnpm res:build` (ReScript compiler) → `pnpm build` (rolldown bundle → `dist/cli/index.js`).

## Providers

OpenAI · opencode Zen · opencode Go · z.ai · Kimi · Minimax · Anthropic · Gemini

**Production-ready**: OpenAI (OAuth WHAM), z.ai, Minimax (via `mmx` CLI binary), Kimi (subscription), Anthropic (Claude subscription via Claude Code login).

OpenAI OAuth tokens from opencode refresh automatically: when the access token is expired or within 60s of expiry (or WHAM answers 401), the CLI exchanges the refresh token at `auth.openai.com/oauth/token` and persists the rotated tokens back to the `openai` entry of opencode's `auth.json` (atomic read-modify-write; other entries untouched). No manual `opencode auth login` needed after the initial one. Tokens from pi are used read-only (see [Credentials](#credentials)).

Anthropic shows your Claude subscription limits (5h session, weekly, weekly per-model) from `GET https://api.anthropic.com/api/oauth/usage`, using the token Claude Code stores after `claude` browser login (`~/.claude/.credentials.json`, or `$CLAUDE_CONFIG_DIR/.credentials.json`). The file is never written: when the token has expired, the CLI reports `Claude Code token expired — run \`claude\` to refresh`. Launching `claude` once refreshes it. Without a Claude Code login, the Anthropic admin org-usage API (admin-scope key + `orgId`) is still used as a fallback.

**Endpoint pending web scraping** (deferred, not implemented): opencode Zen. opencode Go uses the official API `GET https://opencode.ai/zen/go/v1/usage` with the `opencode-go` API key from `auth.json` (written by `/connect` in opencode).

**Endpoints live but credential-blocked**: Gemini (Antigravity `antigravity-accounts.json` required). Adapters activate automatically when the credential appears.

## Installation

```bash
pnpm install         # Runs postinstall: codegen generates schema + catalog
pnpm build          # Runs prebuild: codegen → res:build → rolldown
```

### Usage without global install

```bash
npx opencode-quotas-extended --help         # via npx (npm registry)
pnpm dlx opencode-quotas-extended --help    # via pnpm dlx
```

**As a local dev dependency:**

```bash
npm install -D opencode-quotas-extended    # or: pnpm add -D opencode-quotas-extended
npx opencode-quotas --help
```

**Via npm global install:**

```bash
npm install -g opencode-quotas-extended
opencode-quotas --help
```

## Configuration

Place `.opencode/quotas.json` in the directory where you run the CLI (config is resolved from `process.cwd()`). See `schemas/quotas.schema.json` for the full schema.

### Credentials

The CLI reads the credentials your coding harnesses already store, so no extra login is needed:

| Source | File | Used for |
|---|---|---|
| opencode | `$XDG_DATA_HOME/opencode/auth.json` (default `~/.local/share/opencode/auth.json`) | all providers |
| pi | `$PI_CODING_AGENT_DIR/auth.json` (default `~/.pi/agent/auth.json`) | OpenAI (`openai-codex`), opencode Go, z.ai (`zai`), Kimi (`kimi-coding`), Minimax (`minimax`) |
| Claude Code | `$CLAUDE_CONFIG_DIR/.credentials.json` (default `~/.claude/.credentials.json`) | Anthropic subscription usage |

Resolution order per provider: Claude Code (Anthropic only) → opencode → pi → environment variables → `quotas.json` `credentials` override. A provider that only one harness knows is still found. When a credential is rejected (HTTP 401/403) or expired, the next one is tried; an error is reported only when every candidate fails. Minimax uses its first credential only, because its key path logs the `mmx` CLI in.

Change which harnesses are read, and in what order, with `credentialSources`:

```json
{ "credentialSources": ["pi", "opencode"] }
```

Harnesses not listed are skipped. Only opencode's `auth.json` is ever written (rotated OpenAI tokens); pi and Claude Code files are read-only, because those tools rotate their own tokens.

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

### How the CLI entrypoint works

`dist/cli/index.js` is the rolldown bundle shipped as the `bin` entry for both `opencode-quotas` and `opencode-quotas-extended`. The bundle compares its own realpath against `process.argv[1]` (also resolved through `realpath`) before calling `run()`. This makes the entrypoint symlink-safe: `npm install -g`, `pnpm dlx`, and `npx` all launch the bundle through a `bin/` shim.

## Development

```bash
pnpm test            # Run all ReScript tests (aggregate runner → lib/es6/**/*.test.res.mjs)
pnpm test:res        # Alias for pnpm test (same runner)
pnpm res:build       # ReScript compiler → lib/es6/
pnpm res:dev         # ReScript compiler in watch mode
pnpm codegen         # Run asset codegen (schema + catalog)
pnpm build           # codegen → res:build → rolldown bundle → dist/cli/index.js
pnpm prebuild        # Full build chain (codegen + res:build + rolldown)
bash scripts/check-secrets.sh  # Secret-leak gate
```

## Build pipeline

The production build chain runs in order:

1. `pnpm codegen` (or `postinstall`/`preres:build`/`prebuild`): reads `schemas/quotas.schema.json` and `src/i18n/locales/en.json`, emits deterministic `.res` modules to `src/Infra/ConfigLoader/Schema.res` and `src/i18n/Translator/EnCatalog.res` (both git-ignored).
2. `pnpm res:build`: ReScript compiler produces `lib/es6/` modules.
3. `pnpm build` (rolldown): bundles `lib/es6/src/Cli/Bootstrap.res.mjs` into `dist/cli/index.js`.

## Design Principles

- **Zero secrets in source**: `scripts/check-secrets.sh` rejects `GOCSPX`, `client_secret`, `sk-`, and `Bearer` patterns in `src/`, `scripts/`, and `schemas/`. `auth.json` and `antigravity-accounts.json` are gitignored.
- **Immutable domain**: `QuotaData` is a plain readonly object; no mutable state in the core.
- **Failure isolation**: Each provider adapter runs independently. HTTP/network failures reject so the pipeline records them in its per-provider error map.
- **Generated assets**: Schema and locale are generated at build time, not embedded at runtime. Generated files are deterministic and git-ignored.

## Status

Gates (run locally; CI is intentionally not part of this repository):

| Gate | Result |
|------|--------|
| `pnpm test` | ✅ 59/59 ReScript test files passed |
| `pnpm res:build` | ✅ clean |
| `pnpm build` | ✅ `dist/cli/index.js` produced |
| `bash scripts/check-secrets.sh` | ✅ exit 0 |
| `node dist/cli/index.js --help` | ✅ works under plain Node |

**8 providers**: OpenAI · opencode Zen · opencode Go · z.ai · Kimi · Minimax · Anthropic · Gemini.
One (Zen) is deferred because it would require web scraping. One (Go) now uses the official usage API `GET https://opencode.ai/zen/go/v1/usage`. One (Gemini) is live-but-credential-blocked. Five (OpenAI, z.ai, Kimi, Minimax, Anthropic) are production-ready.

## Legacy archive

`legacy/` contains the archived TypeScript source from the pre-cutover codebase (46 files). This tree is preserved for reference and is not built, tested, or shipped. The TypeScript code was the production implementation before the ReScript cutover; it is no longer maintained.

## Open issues / Caveats

- Anthropic admin-usage endpoint (fallback when no Claude Code login exists): implemented as a mock-only defensive parser with documented-shape fixture (validation-pending until admin-scope credential is available). Requires an Anthropic admin key with `usage:read` scope plus an `orgId`.
- Anthropic subscription endpoint `/api/oauth/usage` is undocumented by Anthropic; its parser was validated against a live response (Max plan) and falls back to the `five_hour` / `seven_day` fields if `limits` disappears.
- Gemini Antigravity quota endpoint (was TODO): implemented via Google's Cloud Code Antigravity API (`fetchAvailableModels`). Reads OAuth refresh_token from `~/.config/opencode/antigravity-accounts.json`.
- OpenAI `/v1/usage` pagination: implemented as a mock-only cursor-based pagination loop (cap 20) on the raw-key platform path. OAuth WHAM path is unchanged.
- Gemini credentials: the adapter activates automatically when credentials appear; no code change needed.
- Prediction/ETTL wiring: the prediction module exists in `src/domain/Prediction.res` but is not connected to the pipeline. Default aggregation is `max`.
