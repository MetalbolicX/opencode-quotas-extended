// Domain barrel — pure zero-I/O core.
export type { QuotaData, QuotaSnapshot, HistoryPoint, RenderMode } from "./types.js";
export { aggregate, aggregateMax, aggregateMin, aggregateMean, aggregateMedian, aggregateMostCritical } from "./aggregation.js";
export type { AggregationStrategy } from "./aggregation.js";
export { predictTimeToLimit } from "./prediction.js";
export { detectReset } from "./reset.js";
