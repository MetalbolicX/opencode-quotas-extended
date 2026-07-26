// Pure domain: immutable 5-group default set for the 5 coding-plan providers.
// Merged at the application layer with user config (user wins on id collision).
import type { AggregationGroup } from "./aggregation.js";

// Five built-in aggregation groups — one per coding-plan provider.
// Strategy: most_critical (needs ETTL history; falls back to first member gracefully).
export const DEFAULT_AGGREGATION_GROUPS: readonly AggregationGroup[] = Object.freeze([
  Object.freeze({ id: "opencode-zen-monthly",    providerId: "zen",     strategy: "most_critical" }),
  Object.freeze({ id: "opencode-go-monthly",     providerId: "go",      strategy: "most_critical" }),
  Object.freeze({ id: "zai-coding-plan-weekly",   providerId: "zai",     strategy: "most_critical" }),
  Object.freeze({ id: "kimi-daily",              providerId: "kimi",     strategy: "most_critical" }),
  Object.freeze({ id: "minimax-monthly",         providerId: "minimax", strategy: "most_critical" }),
]);
