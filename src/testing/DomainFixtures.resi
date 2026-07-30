// Interface for DomainFixtures — exposes 4 test factory functions.
open Domain
open Aggregation

let makeQuotaData: (
  ~id: string,
  ~providerName: string,
  ~used: float,
  ~limit: option<float>,
  ~unit: string=?,
  ~reset: option<Date.t>=?,
  ~window: windowType=?,
  ~info: option<string>=?,
  ~modelId: option<string>=?,
) => quotaData

let makeHistoryPoint: (
  ~timestamp: float,
  ~used: float,
  ~limit: option<float>=?,
) => historyPoint

let makeQuotaSnapshot: (
  ~fetchedAt: Date.t,
  ~data: array<quotaData>,
  ~errors: option<dict<string>>=?,
) => quotaSnapshot

let makeAggregationGroup: (
  ~id: string,
  ~providerId: string,
  ~strategy: aggregationStrategy,
) => aggregationGroup
