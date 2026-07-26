// Pure domain: zero I/O, zero Node built-ins, zero adapter imports.
import type { QuotaData } from "./types.js";

// ── aggregation group config ─────────────────────────────────────────────────

/** Immutable aggregation group — maps a named group to a provider + strategy. */
export interface AggregationGroup {
  readonly id: string;
  readonly providerId: string;
  readonly strategy: AggregationStrategy;
}

// ── ratio helper ──────────────────────────────────────────────────────────────

// Normalise used/limit to [0,1] so strategies work regardless of absolute scale.
// Null limit = unlimited → treated as ratio 0 so max/min strategies skip it.
const ratio = (q: QuotaData): number =>
  q.limit !== null && q.limit > 0 ? q.used / q.limit : 0;

// ── strategies ────────────────────────────────────────────────────────────────
export function aggregateMax(quotas: readonly QuotaData[]): QuotaData | null {
  if (quotas.length === 0) return null;
  return quotas.reduce((a, b) => (ratio(a) > ratio(b) ? a : b));
}

export function aggregateMin(quotas: readonly QuotaData[]): QuotaData | null {
  if (quotas.length === 0) return null;
  return quotas.reduce((a, b) => (ratio(a) < ratio(b) ? a : b));
}

export function aggregateMean(
  quotas: readonly QuotaData[],
  name = "Aggregated",
  id = "agg-mean"
): QuotaData {
  const avgRatio =
    quotas.reduce((s, q) => s + ratio(q), 0) / Math.max(1, quotas.length);
  return { id, providerName: name, used: Math.round(avgRatio * 100), limit: 100, unit: "%", reset: null, predictedReset: null, window: "rolling" };
}

export function aggregateMedian(
  quotas: readonly QuotaData[],
  name = "Aggregated",
  id = "agg-median"
): QuotaData | null {
  if (quotas.length === 0) return null;
  const sorted = [...quotas].sort((a, b) => ratio(a) - ratio(b));
  const mid = sorted[Math.floor(sorted.length / 2)];
  return { id, providerName: name, used: Math.round(ratio(mid) * 100), limit: 100, unit: "%", reset: null, predictedReset: null, window: "rolling" };
}

export function aggregateMostCritical(
  quotas: readonly QuotaData[],
  ettlMap: Record<string, number>
): QuotaData | null {
  if (quotas.length === 0) return null;
  let best: QuotaData | null = null;
  let minTime = Infinity;
  for (const q of quotas) {
    const t = (ettlMap ?? {})[q.id] ?? Infinity;
    // First member with ETTL=Infinity becomes the initial best; subsequent
    // Infinity-ETTL members are skipped so the first encountered is returned.
    if (!best || t < minTime) { minTime = t; best = q; }
  }
  if (!best) return aggregateMax(quotas);
  if (minTime === Infinity) return best;
  return best;
}

// ── dispatcher ────────────────────────────────────────────────────────────────
export type AggregationStrategy = "most_critical" | "max" | "min" | "mean" | "median";

// ── merge: defaults + user config ───────────────────────────────────────────

/**
 * Merge default aggregation groups with user-supplied groups.
 * User groups WIN on id collision (replace the default of the same id).
 * Defaults that have no user override are appended in original order.
 *
 * @param userGroups    — user-configured AggregationGroup[] (may be empty)
 * @param defaultGroups — built-in AggregationGroup[] (e.g. DEFAULT_AGGREGATION_GROUPS)
 * @returns frozen merged array; caller must not mutate
 */
export function mergeAggregationGroups(
  userGroups: readonly AggregationGroup[],
  defaultGroups: readonly AggregationGroup[],
): readonly AggregationGroup[] {
  // Map-based merge: defaults seeded first, user groups overwrite on collision.
  // Iteration order of Map.values() follows insertion order (defaults → user wins).
  const map = new Map<string, AggregationGroup>();

  // Seed with defaults; user groups will overwrite on collision
  for (const g of defaultGroups) {
    map.set(g.id, g);
  }

  // User wins on id collision
  for (const g of userGroups) {
    map.set(g.id, g);
  }

  return Object.freeze(Array.from(map.values()));
}

export function aggregate(
  quotas: readonly QuotaData[],
  strategy: AggregationStrategy,
  ettlMap?: Record<string, number>
): QuotaData | null {
  switch (strategy) {
    case "most_critical": return aggregateMostCritical(quotas, ettlMap ?? {});
    case "max":           return aggregateMax(quotas);
    case "min":           return aggregateMin(quotas);
    case "mean":          return aggregateMean(quotas);
    case "median":        return aggregateMedian(quotas);
  }
}
