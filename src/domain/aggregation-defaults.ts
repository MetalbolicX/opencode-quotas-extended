// Pure domain: immutable 5-group default set for the 5 coding-plan providers.
// Merged at the application layer with user config (user wins on id collision).
import type { AggregationGroup } from "./aggregation.js";

// Five built-in aggregation groups — one per coding-plan provider.
// Strategy: max. ETTL-based "most_critical" is not wired in this release (the
// prediction module exists but requires accumulated history data).
export const DEFAULT_AGGREGATION_GROUPS: readonly AggregationGroup[] = Object.freeze([
  Object.freeze({ id: "opencode-zen-monthly",    providerId: "zen",     strategy: "max" }),
  Object.freeze({ id: "opencode-go-monthly",     providerId: "go",      strategy: "max" }),
  Object.freeze({ id: "zai-coding-plan-weekly",   providerId: "zai",     strategy: "max" }),
  Object.freeze({ id: "kimi-daily",              providerId: "kimi",     strategy: "max" }),
  Object.freeze({ id: "minimax-monthly",         providerId: "minimax", strategy: "max" }),
]);
