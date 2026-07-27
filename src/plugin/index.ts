// Plugin entry — satisfies opencode Plugin type.
// Returns { 'experimental.text.complete': handleTextComplete }.
import type { Plugin } from "@opencode-ai/plugin";
import { handleTextComplete } from "./footer-hook.js";
import { PluginState } from "./state.js";
import { DEFAULTS, loadConfig } from "../adapters/infra/config-loader.js";
import { createCredentialResolver } from "../adapters/auth/credential-resolver.js";
import { FetchHttpClient } from "../adapters/infra/fetch-http.js";
import { buildDefaultRegistry } from "../adapters/providers/registry.js";
import { QuotaCache } from "../adapters/infra/quota-cache.js";
import { reportQuotas } from "../application/report-pipeline.js";
import type { CacheSource } from "../ports/cache.js";
import { existsSync } from "node:fs";
import { join } from "node:path";

/** Default footer signature — marks "footer already injected" in output.text */
const FOOTER_SIGNATURE = "<!-- quota-footer -->";

// No-op logger — plugin does not emit diagnostic output.
const noopLogger = { debug() {}, info() {}, warn() {}, error() {} };

/** Minimal no-op history store — history is not persisted in plugin mode. */
function createNoopHistory() {
  return {
    append: async (_id: string, _pt: { timestamp: number; used: number; limit: number | null }) => {},
    getHistory: async (_id: string, _ms: number) => [] as { timestamp: number; used: number; limit: number | null }[],
    prune: async (_ms: number) => {},
    resetDetected: () => false,
  };
}

export default (async ({ directory }: { directory: string }) => {
  // Injectable clock for PluginState time-based dedup.
  const clock = () => Date.now();
  const pluginState = new PluginState(clock);

  // Load the FULL QuotasConfig (not just show) so the pipeline has the same
  // behavior as the CLI: displayMode, disabled, aggregatedGroups, showUnaggregated,
  // progressBar, pollingInterval, filterByCurrentModel, anthropic.orgId, credentials.
  // Fall back to DEFAULTS when no config file exists.
  const configPath = join(directory, ".opencode", "quotas.json");
  const config = existsSync(configPath) ? loadConfig(configPath) : { ...DEFAULTS };

  // Bootstrap the shared pipeline dependencies ONCE at factory scope (not per-hook-fire).
  // This mirrors the CLI bootstrap in src/cli/index.ts and avoids repeated setup cost.
  const credentialResolver = createCredentialResolver(
    config,
    { readFileSync: (p) => require("node:fs").readFileSync(p, "utf-8") },
    process.env as Record<string, string | undefined>,
  );
  const httpClient = new FetchHttpClient(noopLogger);
  const registry = buildDefaultRegistry(credentialResolver, httpClient);
  const historyStore = createNoopHistory();

  // QuotaCache is MANDATORY: without it every experimental.text.complete fire would
  // issue N×8 live HTTP requests.  The cache provides immediate return (last snapshot)
  // and coalesces concurrent callers onto a single in-flight fetch (single-flight).
  // Interval comes from config.pollingInterval (default 0 = fetch-once per hook fire).
  const cache: CacheSource = new QuotaCache(
    // Fetcher: calls all providers in the registry and flattens results.
    async () => {
      const providers = registry.list();
      const results = await Promise.allSettled(
        providers.map((p) => (p as any).fetchQuotas()),
      );
      const allData: any[] = [];
      for (let i = 0; i < results.length; i++) {
        if (results[i].status === "fulfilled") {
          allData.push(...(results[i] as PromiseFulfilledResult<any>).value);
        }
      }
      return allData;
    },
    { interval: config.pollingInterval ?? 0 },
  );

  // reportQuotas deps — all infrastructure resolved at factory scope, reused across hook fires.
  const pipelineDeps = {
    credentialResolver,
    httpClient,
    registry,
    historyStore,
    cache,
    config: {
      displayMode: config.displayMode,
      disabled: config.disabled,
      aggregatedGroups: config.aggregatedGroups,
      historyMaxAgeHours: config.historyMaxAgeHours,
      predictionWindowMinutes: config.predictionWindowMinutes,
      predictionShortWindowMinutes: config.predictionShortWindowMinutes,
      showUnaggregated: config.showUnaggregated,
      progressBar: config.progressBar,
    },
    logger: noopLogger,
  };

  /**
   * Renders the compact quota footer via the shared in-process report-pipeline.
   *
   * Why in-process (not shell-out via $):
   *   The slice-9 shell-out plan was abandoned.  Calling reportQuotas directly
   *   avoids subprocess spawn overhead and reuses the already-bootstrapped registry,
   *   credential resolver, HTTP client, and cache — so the footer renders from
   *   warm cache state on subsequent hook fires.
   *
   * Why compact=true:
   *   The footer must be narrow and readable on a single terminal line.
   *   compact=true drops the reset (time-to-next-reset) and ettl (predicted-reset)
   *   columns while preserving the bar (█/░), percent, and provider name.
   *   /quotas (full CLI) uses compact=false and retains all six columns.
   *
   * Why displayMode from config:
   *   The same displayMode (table|json|markdown) applies to both the footer and
   *   /quotas output.  table is the default and produces the ASCII bar chars.
   *
   * @returns fenced text block suitable for appending to assistant output
   */
  async function renderFooter(): Promise<string> {
    try {
      // compact=true: narrow footer layout (name/bar/percent/status only).
      // mode from config: table|json|markdown — shared with /quotas output.
      const { rendered } = await reportQuotas(pipelineDeps, {
        mode: config.displayMode,
        compact: true,
        now: Date.now(),
      });
      if (!rendered) return ""; // no data — return empty so no fence is appended
      return "```text\n" + rendered + "\n```";
    } catch (err) {
      // Fail gracefully: redacted warning + empty footer (hook continues, output is not broken).
      console.warn("[opencode-quotas] footer render failed:", (err as Error).message);
      return "";
    }
  }

  const deps = {
    pluginState,
    renderFooter,
    signature: FOOTER_SIGNATURE,
    show: config.show,
  };

  return {
    "experimental.text.complete": async (
      input: { sessionID: string; messageID: string; partID: string },
      output: { text: string },
    ) => {
      await handleTextComplete(input, output, deps);
    },
  };
}) satisfies Plugin;
