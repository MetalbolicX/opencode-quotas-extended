// Domain module -- re-exports all pure domain types and functions.
// Zero I/O. Zero adapter imports. Domain depends ONLY on ports (DIP).
// This is the single re-export point for the domain layer.

module Types = Types
module Aggregation = Aggregation
module AggregationDefaults = AggregationDefaults
module Reset = Reset
module Prediction = Prediction

// Re-export commonly used types (except aggregationGroup -- opaque alias causes
// field-access compilation errors in downstream test files that need record fields).
type quotaData = Types.quotaData
type quotaSnapshot = Types.quotaSnapshot
type historyPoint = Types.historyPoint
type renderMode = Types.renderMode
type windowType = Types.windowType
type aggregationStrategy = Types.aggregationStrategy
// aggregationGroup intentionally omitted -- use Aggregation.aggregationGroup directly.
// Provider port types (authStrategy, quotaProvider) live in the Provider module, not here.

let aggregate = Aggregation.aggregate
let aggregateMax = Aggregation.aggregateMax
let aggregateMin = Aggregation.aggregateMin
let aggregateMean = Aggregation.aggregateMean
let aggregateMedian = Aggregation.aggregateMedian
let aggregateMostCritical = Aggregation.aggregateMostCritical
let mergeAggregationGroups = Aggregation.mergeAggregationGroups

let defaultAggregationGroups = AggregationDefaults.defaultAggregationGroups

let detectReset = Reset.detectReset

let predictTimeToLimit = Prediction.predictTimeToLimit

// Re-export helper functions from Types
let windowToString = Types.windowToString
let windowFromString = Types.windowFromString
let renderModeToString = Types.renderModeToString
let renderModeFromString = Types.renderModeFromString
let strategyToString = Types.strategyToString
let strategyFromString = Types.strategyFromString


