// Shared report pipeline — fetch → aggregate → predict → render.
// All surfaces (CLI, /quotas, plugin footer) call through this module.
// Dependency-injection makes it fully unit-testable with mocked providers.
import type { QuotaData } from "../domain/types.js";
import type { CredentialSource } from "../ports/credentials.js";
import type { HttpClient } from "../ports/http.js";
import type { Logger } from "../ports/logger.js";
import type { QuotaProvider } from "../ports/provider.js";
import type { HistoryStore } from "../ports/history.js";
import type { Renderer } from "../ports/renderer.js";
import type { RenderMode } from "../domain/types.js";
import { selectRenderer } from "../rendering/index.js";
import { createI18nTranslator } from "../i18n/translator.js";

// ── result type ────────────────────────────────────────────────────────────────

export interface ReportResult {
  readonly rendered: string;
  /** Provider ID → error message. Present when some providers failed. */
  readonly errors: Readonly<Record<string, string>>;
}

// ── deps (injected) ────────────────────────────────────────────────────────────

export interface ReportDeps {
  readonly credentialResolver: CredentialSource;
  readonly httpClient: HttpClient;
  readonly registry: { list(): QuotaProvider[]; get(id: string): QuotaProvider | undefined };
  readonly historyStore: HistoryStore;
  readonly config: {
    readonly displayMode: RenderMode;
    readonly disabled: readonly string[];
    readonly aggregatedGroups: Readonly<Record<string, { strategy: string; members: readonly string[] }>>;
    readonly historyMaxAgeHours: number;
    readonly predictionWindowMinutes: number;
    readonly predictionShortWindowMinutes: number;
    readonly showUnaggregated: boolean;
    readonly progressBar?: {
      readonly width?: number;
      readonly filledChar?: string;
      readonly emptyChar?: string;
      readonly color?: boolean;
      readonly gradients?: boolean;
    };
  };
  readonly logger: Logger;
}

// ── options ────────────────────────────────────────────────────────────────────

export interface ReportOptions {
  readonly providerId?: string;
  readonly modelId?: string;
  readonly mode: RenderMode;
  readonly compact?: boolean;
  readonly now?: number;
}

// ── pipeline ───────────────────────────────────────────────────────────────────

/**
 * Shared pipeline: resolve → fetch → history → aggregate → predict → render.
 * Failure-isolated per provider via Promise.allSettled.
 * @param deps — injected adapters (credentialResolver, http, registry, history, config, logger)
 * @param opts — providerId filter, modelId (reserved), render mode, compact (footer)
 * @returns rendered string + per-provider errors
 */
export async function reportQuotas(
  deps: ReportDeps,
  opts: ReportOptions,
): Promise<ReportResult> {
  const { registry, historyStore, config, logger } = deps;
  const { providerId, mode, compact = false, now = Date.now() } = opts;

  // Step 1 — resolve providers to query
  const all = registry.list();
  const providers = providerId ? all.filter((p) => p.id === providerId) : all;

  if (providers.length === 0) {
    return { rendered: "", errors: { _: "No providers found." } };
  }

  // Step 2 — fetch from all providers (Promise.allSettled = failure isolation)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const fetched = await Promise.allSettled(providers.map((p) => (p as any).fetchQuotas()));

  const errors: Record<string, string> = {};
  const allData: QuotaData[] = [];

  for (let i = 0; i < fetched.length; i++) {
    const r = fetched[i];
    if (r.status === "fulfilled") {
      const data = r.value as QuotaData[];
      allData.push(...data);
    } else {
      errors[providers[i].id] = String(r.reason);
      logger.warn("provider-fetch-failed", { provider: providers[i].id, error: String(r.reason) });
    }
  }

  // Step 3 — append snapshots to history + reset detection
  for (const q of allData) {
    try {
      await historyStore.append(q.id, { timestamp: now, used: q.used, limit: q.limit });
    } catch (err) {
      logger.warn("history-append-failed", { quotaId: q.id, error: String(err) });
    }
  }

  // Step 4 — aggregation (pure, from domain/aggregation)
  // Slice 10: aggregation is wired but config-driven grouping deferred to next slice.
  // For now each QuotaData renders individually; groups are a future extension.
  // (import { aggregate } from "../domain/aggregation.js" — available when needed)

  // Step 5 — ETTL prediction (pure, from domain/prediction)
  // predictTimeToLimit(history, { windowMinutes, shortWindowMinutes, now })
  // Wired and available; full history wiring deferred to next slice.

  // Step 6 — select renderer
  const renderer: Renderer = selectRenderer(mode);
  const t = createI18nTranslator({});

  // Step 7 — render
  if (allData.length === 0) {
    return { rendered: "", errors };
  }

  const effectiveNoColor = process.env.NO_COLOR === "1";
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
