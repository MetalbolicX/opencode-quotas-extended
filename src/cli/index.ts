// CLI entry — opencode-quotas.
// Flags: --provider <id> --model <id> --mode <table|json|markdown> --no-color
// Bootstrap: configLoader → credentialResolver → httpClient → registry → fetch → aggregate → predict → render → stdout.
// Exit: 0 render success, 1 no providers / fatal.

import { existsSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { RenderMode } from "../domain/types.js";
import { DEFAULTS, loadConfig } from "../adapters/infra/config-loader.js";
import { createCredentialResolver } from "../adapters/auth/credential-resolver.js";
import { FetchHttpClient } from "../adapters/infra/fetch-http.js";
import { buildDefaultRegistry } from "../adapters/providers/registry.js";
import { selectRenderer } from "../rendering/index.js";
import { createI18nTranslator } from "../i18n/translator.js";
import type { Logger } from "../ports/logger.js";
import type { QuotaData } from "../domain/types.js";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const ROOT = join(__dirname, "..", "..");

// ── Args parsing ──────────────────────────────────────────────────────────────

export interface CliArgs {
  provider?: string;
  model?: string;
  mode: RenderMode;
  noColor: boolean;
}

export function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = { mode: "table", noColor: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--provider" && argv[i + 1]) args.provider = argv[++i];
    else if (a === "--model" && argv[i + 1]) args.model = argv[++i];
    else if (a === "--mode" && argv[i + 1]) args.mode = argv[++i] as RenderMode;
    else if (a === "--no-color") args.noColor = true;
  }
  return args;
}

// ── No-op logger ─────────────────────────────────────────────────────────────

const noopLogger: Logger = {
  debug() {},
  info() {},
  warn() {},
  error() {},
};

// ── reportQuotas — inline pipeline (Slice 9 minimal; Slice 10 extracts) ──────

export interface ReportResult {
  readonly rendered: string;
  readonly errors: Record<string, string>;
}

export interface ReportOptions {
  readonly providerId?: string;
  readonly modelId?: string;
  readonly mode: RenderMode;
  readonly noColor: boolean;
}

export async function reportQuotas(opts: ReportOptions): Promise<ReportResult> {
  const { providerId, mode, noColor } = opts;

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
  const registry = buildDefaultRegistry(
    { get: (id) => credentialResolver.get(id) },
    http,
  );

  // Filter
  const providers = registry.list().filter(
    (p) => !providerId || p.id === providerId,
  );

  if (providers.length === 0) {
    return { rendered: "", errors: { _: "No providers found." } };
  }

  // Fetch from all (or filtered) providers
  // NOTE: all provider implementations take 0 args (credential resolution is internal).
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const fetched = await Promise.allSettled(
    providers.map((p) => (p as any).fetchQuotas()),
  );

  const errors: Record<string, string> = {};
  const allData: QuotaData[] = [];

  for (let i = 0; i < fetched.length; i++) {
    const r = fetched[i];
    if (r.status === "fulfilled") {
      allData.push(...r.value);
    } else {
      errors[providers[i].id] = String(r.reason);
    }
  }

  // Render all fetched data directly (no history → no prediction in Slice 9)
  // Slice 10 will wire in history store + ETTL prediction.
  if (allData.length === 0) {
    return { rendered: "", errors };
  }

  const renderer = selectRenderer(mode);
  const t = createI18nTranslator({});
  const effectiveNoColor = noColor || process.env.NO_COLOR === "1";
  const rendered = renderer.render(allData, {
    mode,
    noColor: effectiveNoColor,
    progressBar: config.progressBar ? {
      width: config.progressBar.width ?? 20,
      filledChar: config.progressBar.filledChar ?? "█",
      emptyChar: config.progressBar.emptyChar ?? "░",
      color: config.progressBar.color ?? true,
      gradients: config.progressBar.gradients ?? false,
    } : undefined,
    t,
  });

  return { rendered, errors };
}

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

    const result = await reportQuotas({
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
