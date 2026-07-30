// Domain.resi — barrel interface re-exporting all pure domain types and functions.
// Factories have been moved to DomainFixtures. The domain layer is zero I/O.
//
// NOTE: submodules (Types, Aggregation, etc.) are re-exported via their own .resi
// files and are accessible as Domain.Types, Domain.Aggregation, etc.

type quotaData = Types.quotaData
type quotaSnapshot = Types.quotaSnapshot
type historyPoint = Types.historyPoint
type renderMode = Types.renderMode
type windowType = Types.windowType
type aggregationStrategy = Types.aggregationStrategy

let aggregate: (array<quotaData>, aggregationStrategy, ~ettlMap: dict<float>=?) => option<quotaData>
let aggregateMax: array<quotaData> => option<quotaData>
let aggregateMin: array<quotaData> => option<quotaData>
let aggregateMean: (array<quotaData>, ~name: string=?, ~id: string=?) => quotaData
let aggregateMedian: (array<quotaData>, ~name: string=?, ~id: string=?) => option<quotaData>
let aggregateMostCritical: (array<quotaData>, dict<float>) => option<quotaData>
let mergeAggregationGroups: (array<Aggregation.aggregationGroup>, array<Aggregation.aggregationGroup>) => array<Aggregation.aggregationGroup>

let defaultAggregationGroups: array<Aggregation.aggregationGroup>

let detectReset: (historyPoint, quotaData) => bool

let predictTimeToLimit: (array<historyPoint>, ~params: Prediction.predictionParams=?) => float

let windowToString: windowType => string
let windowFromString: string => option<windowType>
let renderModeToString: renderMode => string
let renderModeFromString: string => option<renderMode>
let strategyToString: aggregationStrategy => string
let strategyFromString: string => option<aggregationStrategy>

