// CLI entry — opencode-quotas.
// Flags: --provider <id> --model <id> --mode <table|json|markdown> --no-color
// Bootstrap: configLoader → credentialResolver → httpClient → registry → shared-pipeline → stdout.
// Exit: 0 render success, 1 no providers / fatal.
//
// Slice 10: The inline pipeline has been extracted to src/application/report-pipeline.ts.
// This CLI now delegates to the shared module for all surfaces.

import { existsSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { RenderMode } from "../domain/types.js";
import { DEFAULTS, loadConfig } from "../adapters/infra/config-loader.js";
import { createCredentialResolver } from "../adapters/auth/credential-resolver.js";
import { FetchHttpClient } from "../adapters/infra/fetch-http.js";
import { buildDefaultRegistry } from "../adapters/providers/registry.js";
import { filterAvailableProviders } from "../adapters/providers/filter.js";
import type { Logger } from "../ports/logger.js";
import { reportQuotas as pipeline } from "../application/report-pipeline.js";
import type { ReportResult } from "../application/report-pipeline.js";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const ROOT = join(__dirname, "..", "..");

// ── Args parsing ──────────────────────────────────────────────────────────────

export interface CliArgs {
  provider?: string;
  model?: string;
  mode: RenderMode;
  noColor: boolean;
  /** When true, emit numbered availability table instead of fetching quota data. */
  list: boolean;
}

export function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = { mode: "table", noColor: false, list: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--provider" && argv[i + 1]) args.provider = argv[++i];
    else if (a === "--model" && argv[i + 1]) args.model = argv[++i];
    else if (a === "--mode" && argv[i + 1]) args.mode = argv[++i] as RenderMode;
    else if (a === "--no-color") args.noColor = true;
    else if (a === "--list") args.list = true;
  }
  return args;
}

// ── No-op logger (CLI doesn't emit debug/info; errors surface via result) ─────

const noopLogger: Logger = { debug() {}, info() {}, warn() {}, error() {} };

// ── List mode renderer ────────────────────────────────────────────────────────

/**
 * Renders a numbered availability table for the --list picker.
 * Columns: #, id, displayName, status, percent, availability
 * Status/percent are "—" (synthetic) since no fetchQuotas is made in list mode.
 */
function renderListTable(
  providers: Array<{ id: string; displayName: string }>,
): string {
  const rows = providers.map((p, i) => {
    const num = `${i + 1}`;
    const id = p.id;
    const name = p.displayName;
    // Status/percent are synthetic "—" in availability-only list mode
    const status = "—";
    const pct = "—";
    const avail = "available";
    return [num, id, name, status, pct, avail].join("  ");
  });
  const header = ["#", "id", "displayName", "status", "percent", "availability"].join("  ");
  return [header, ...rows].join("\n");
}

// ── Shared reportQuotas (backward-compatible wrapper) ─────────────────────────
// Re-exports the pipeline as a factory so tests can inject deps when needed.

export interface ReportOptions {
  readonly providerId?: string;
  readonly modelId?: string;
  readonly mode: RenderMode;
  readonly noColor: boolean;
}

/**
 * Creates a reportQuotas function bound to the CLI's filesystem/bootstrap context.
 * The underlying call goes through src/application/report-pipeline.ts.
 */
export function createReportQuotas() {
  return async function reportQuotas(opts: ReportOptions): Promise<ReportResult> {
    const { providerId, modelId, mode, noColor } = opts;

    // Config
    const configPath = join(ROOT, ".opencode", "quotas.json");
    const config = existsSync(configPath) ? loadConfig(configPath) : DEFAULTS;

    // Credentials
    const credentialResolver = createCredentialResolver(
      config,
      { readFileSync: (p) => require("node:fs").readFileSync(p, "utf-8") },
      process.env as Record<string, string | undefined>,
    );

    // HTTP + registry
    const http = new FetchHttpClient(noopLogger);
    const registry = buildDefaultRegistry({ get: (id) => credentialResolver.get(id) }, http);

    // Delegate to shared pipeline
    return pipeline(
      { credentialResolver, httpClient: http, registry, historyStore: createNoopHistory(), config, logger: noopLogger },
      { providerId, modelId, mode, now: Date.now() },
    );
  };
}

// Minimal no-op history store for CLI bootstrap (no persistence in CLI mode)
function createNoopHistory() {
  return {
    append: async (_id: string, _point: { timestamp: number; used: number; limit: number | null }) => {},
    getHistory: async (_id: string, _ms: number) => [] as { timestamp: number; used: number; limit: number | null }[],
    prune: async (_ms: number) => {},
    resetDetected: (_id: string, _prev: { timestamp: number; used: number; limit: number | null }, _used: number, _limit: number | null) => false,
  };
}

// Default instance for CLI use
const _reportQuotas = createReportQuotas();

// ── run — testable entry point ────────────────────────────────────────────────

export interface RunResult {
  readonly stdout: string;
  readonly exitCode: number;
}

const USAGE = `opencode-quotas — display AI provider quota usage.

Usage: opencode-quotas [flags]

Flags:
  --provider <id>   Filter to a single provider (e.g. openai, anthropic)
  --model <id>      Filter to a specific model (reserved for future use)
  --mode <mode>     Output format: table (default), json, markdown
  --no-color        Strip ANSI color codes from output
  --list            Show available providers as a numbered list (for picker)
  --help            Show this usage information
`.trim();

export async function run(argv: string[]): Promise<RunResult> {
  try {
    const args = parseArgs(argv);

    if (args.noColor) process.env.NO_COLOR = "1";

    if (argv.includes("--help")) {
      process.stdout.write(USAGE + "\n");
      return { stdout: USAGE, exitCode: 0 };
    }

    // REQ-LIST-3: --list and --provider are mutually exclusive
    if (args.list && args.provider) {
      const msg = "Cannot combine --list and --provider";
      process.stdout.write(msg + "\n");
      return { stdout: msg, exitCode: 1 };
    }

    // Config
    const configPath = join(ROOT, ".opencode", "quotas.json");
    const config = existsSync(configPath) ? loadConfig(configPath) : DEFAULTS;

    // Credentials
    const credentialResolver = createCredentialResolver(
      config,
      { readFileSync: (p) => require("node:fs").readFileSync(p, "utf-8") },
      process.env as Record<string, string | undefined>,
    );

    // HTTP + registry
    const http = new FetchHttpClient(noopLogger);
    const registry = buildDefaultRegistry({ get: (id) => credentialResolver.get(id) }, http);

    // REQ-LIST: --list mode renders availability table
    if (args.list) {
      const all = registry.list();
      // Filter to only available providers (no fetchQuotas in list mode)
      const available = await filterAvailableProviders(all);

      // REQ-LIST-2: exit 1 when registry is empty
      if (available.length === 0) {
        return { stdout: "", exitCode: 1 };
      }

      const rendered = renderListTable(
        available.map((p) => ({ id: p.id, displayName: p.displayName })),
      );
      process.stdout.write(rendered + "\n");
      return { stdout: rendered, exitCode: 0 };
    }

    const result = await _reportQuotas({
      providerId: args.provider,
      modelId: args.model,
      mode: args.mode,
      noColor: args.noColor,
    });

    if (result.errors["_"]) {
      process.stdout.write(result.errors["_"] + "\n");
      return { stdout: result.errors["_"], exitCode: 1 };
    }

    process.stdout.write(result.rendered + "\n");
    return { stdout: result.rendered, exitCode: 0 };
  } catch (err) {
    process.stderr.write(`Fatal: ${err instanceof Error ? err.message : String(err)}\n`);
    return { stdout: "", exitCode: 1 };
  }
}

// ── Top-level bootstrap ───────────────────────────────────────────────────────

const IS_MAIN = process.argv[1]?.endsWith("cli/index.ts") ||
  process.argv[1]?.endsWith("cli/index.js");
if (IS_MAIN) {
  run(process.argv.slice(2)).then((r) => process.exit(r.exitCode));
}
