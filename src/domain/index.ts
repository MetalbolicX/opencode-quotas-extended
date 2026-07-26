// Domain barrel — pure zero-I/O core.
export type { QuotaData, QuotaSnapshot, HistoryPoint, RenderMode } from "./types.js";
export { aggregate, aggregateMax, aggregateMin, aggregateMean, aggregateMedian, aggregateMostCritical, mergeAggregationGroups } from "./aggregation.js";
export type { AggregationGroup, AggregationStrategy } from "./aggregation.js";
export { predictTimeToLimit } from "./prediction.js";
export { detectReset } from "./reset.js";
export { DEFAULT_AGGREGATION_GROUPS } from "./aggregation-defaults.js";
