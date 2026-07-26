# opencode-quotas-extended

Hexagonal rewrite of the opencode-quotas plugin with SOLID/clean architecture, extended provider list, and strict TDD.

## Overview

This plugin provides AI provider quota monitoring and prediction for the opencode editor. It renders usage status (OK/WRN/ERR) with progress bars, aggregates multi-provider data, and predicts reset times using dual-window linear regression.

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

## Providers

OpenAI · opencode Zen · opencode Go · z.ai · Kimi · Minimax · Anthropic · Gemini

## Configuration

Place `.opencode/quotas.json` in your project root. See `schemas/quotas.schema.json` for the full schema.

## Commands

- `/quotas` — Render the full quota report in your opencode session.

## CLI

```bash
bun run build       # Compile TypeScript to dist/
bun run test        # Run all tests
bun run test:coverage  # Run tests with coverage
bun run typecheck   # TypeScript type checking
bash scripts/check-secrets.sh  # CI secret-leak gate
```

## Design Principles

- **Zero secrets in source**: CI gate rejects any `GOCSPX`, `client_secret`, or `sk-` pattern.
- **Immutable domain**: `QuotaData` is a plain readonly object; no mutable state in the core.
- **Failure isolation**: Each provider adapter runs independently; a single provider failure does not crash the report.
- **TDD-first**: Every behavior is driven by a failing test before implementation.
