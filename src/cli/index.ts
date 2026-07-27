// CLI entry — opencode-quotas.
// Flags: -l/--list -p/--provider -c/--color -m/--mode -h/--help
// Bootstrap: configLoader → credentialResolver → httpClient → registry → shared-pipeline → stdout.
// Exit: 0 render success, 1 partial/diagnostic, 2 usage error.
//
// Slice 10: The inline pipeline has been extracted to src/application/report-pipeline.ts.
// This CLI now delegates to the shared module for all surfaces.

import { existsSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { RenderMode } from "../domain/types.js";
import { parseArgs } from "./parse-args.js";
import { DEFAULTS, loadConfig } from "../adapters/infra/config-loader.js";
import { createCredentialResolver } from "../adapters/auth/credential-resolver.js";
import { FetchHttpClient } from "../adapters/infra/fetch-http.js";
import { buildDefaultRegistry } from "../adapters/providers/registry.js";
import { filterAvailableProviders } from "../adapters/providers/filter.js";
import type { Logger } from "../ports/logger.js";
import { reportQuotas as pipeline } from "../application/report-pipeline.js";
import type { ReportResult } from "../application/report-pipeline.js";
import { COLOR_MAP } from "../rendering/colors.js";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const ROOT = join(__dirname, "..", "..");

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
  readonly color?: string;
}

/**
 * Creates a reportQuotas function bound to the CLI's filesystem/bootstrap context.
 * The underlying call goes through src/application/report-pipeline.ts.
 */
export function createReportQuotas() {
  return async function reportQuotas(opts: ReportOptions): Promise<ReportResult> {
    const { providerId, modelId, mode, color } = opts;

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
      { providerId, modelId, mode, color, now: Date.now() },
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

// ── USAGE ────────────────────────────────────────────────────────────────────

const VALID_COLORS = Object.keys(COLOR_MAP).join(", ");

const USAGE = `opencode-quotas — display AI provider quota usage.

Usage: opencode-quotas [flags]

Flags:
  -l, --list            Show available providers as a numbered list (default when no flags)
  -p, --provider <id>   Filter to a single provider (e.g. openai, anthropic)
  -c, --color <name>    Color for the usage bar: ${VALID_COLORS}
  -m, --mode <mode>     Output format: table (default), json, markdown
  -h, --help            Show this usage information
`.trim();

// ── run — testable entry point ────────────────────────────────────────────────

export interface RunResult {
  readonly stdout: string;
  readonly stderr: string;
  readonly exitCode: number;
}

export async function run(argv: string[]): Promise<RunResult> {
  let stderr = "";

  try {
    const args = parseArgs(argv);

    if (args.help) {
      process.stdout.write(USAGE + "\n");
      return { stdout: USAGE + "\n", stderr: "", exitCode: 0 };
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

    // REQ-CLI-1: --list mode renders availability table
    if (args.list) {
      const all = registry.list();
      // Filter to only available providers (no fetchQuotas in list mode)
      const available = await filterAvailableProviders(all);

      // REQ-LIST-2: exit 1 when registry is empty
      if (available.length === 0) {
        return { stdout: "", stderr: "", exitCode: 1 };
      }

      const rendered = renderListTable(
        available.map((p) => ({ id: p.id, displayName: p.displayName })),
      );
      process.stdout.write(rendered + "\n");
      return { stdout: rendered + "\n", stderr: "", exitCode: 0 };
    }

    const result = await _reportQuotas({
      providerId: args.provider,
      mode: args.mode,
      color: args.color,
    });

    if (result.errors["_"]) {
      process.stdout.write(result.errors["_"] + "\n");
      return { stdout: result.errors["_"] + "\n", stderr: "", exitCode: 1 };
    }

    process.stdout.write(result.rendered + "\n");
    return { stdout: result.rendered + "\n", stderr: "", exitCode: 0 };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(`${msg}\n${USAGE}\n`);
    return { stdout: "", stderr: `${msg}\n${USAGE}\n`, exitCode: 2 };
  }
}

// ── Top-level bootstrap ───────────────────────────────────────────────────────

const IS_MAIN = process.argv[1]?.endsWith("cli/index.ts") ||
  process.argv[1]?.endsWith("cli/index.js");
if (IS_MAIN) {
  run(process.argv.slice(2)).then((r) => process.exit(r.exitCode));
}
