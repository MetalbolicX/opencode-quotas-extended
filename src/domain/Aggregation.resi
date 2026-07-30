// Aggregation.resi — public surface of the pure domain aggregation module.
// Exposes aggregation strategies and group merging; internal helpers are private.
open Types

type aggregationGroup = {
  id: string,
  providerId: string,
  strategy: aggregationStrategy,
}

let aggregate: (array<quotaData>, aggregationStrategy, ~ettlMap: dict<float>=?) => option<quotaData>
let aggregateMax: array<quotaData> => option<quotaData>
let aggregateMin: array<quotaData> => option<quotaData>
let aggregateMean: (array<quotaData>, ~name: string=?, ~id: string=?) => quotaData
let aggregateMedian: (array<quotaData>, ~name: string=?, ~id: string=?) => option<quotaData>
let aggregateMostCritical: (array<quotaData>, dict<float>) => option<quotaData>
let mergeAggregationGroups: (array<aggregationGroup>, array<aggregationGroup>) => array<aggregationGroup>
