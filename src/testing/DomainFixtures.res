// Test-only domain fixtures — pure factories for test data construction.
// These were moved from src/domain/Types.res and src/domain/Aggregation.res.
// Domain modules must remain free of test concerns; tests import fixtures explicitly.
open Domain
open Aggregation

let makeQuotaData = (
  ~id: string,
  ~providerName: string,
  ~used: float,
  ~limit: option<float>,
  ~unit: string="requests",
  ~reset: option<Date.t>=None,
  ~window: windowType=#daily,
  ~info: option<string>=None,
  ~modelId: option<string>=None,
): quotaData => {
  id,
  providerName,
  used,
  limit,
  unit,
  reset,
  window,
  info,
  modelId,
}

let makeHistoryPoint = (
  ~timestamp: float,
  ~used: float,
  ~limit: option<float>=None,
): historyPoint => {
  timestamp,
  used,
  limit,
}

let makeQuotaSnapshot = (
  ~fetchedAt: Date.t,
  ~data: array<quotaData>,
  ~errors: option<dict<string>>=None,
): quotaSnapshot => {
  fetchedAt,
  data,
  errors,
}

let makeAggregationGroup = (
  ~id: string,
  ~providerId: string,
  ~strategy: aggregationStrategy,
): aggregationGroup => {
  id,
  providerId,
  strategy,
}
