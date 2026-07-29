// Pure domain: zero I/O, zero Node built-ins, zero adapter imports.
open Types

// -- aggregation group config -------------------------------------------------

/** Immutable aggregation group -- maps a named group to a provider + strategy. */
type aggregationGroup = {
  id: string,
  providerId: string,
  strategy: aggregationStrategy,
}

// -- helpers -----------------------------------------------------------------

let floatMax = (a: float, b: float): float => a > b ? a : b

// -- ratio helper --------------------------------------------------------------

// Normalise used/limit to [0,1] so strategies work regardless of absolute scale.
// Null limit = unlimited → treated as ratio 0 so max/min strategies skip it.
let ratio = (q: quotaData): float => {
  switch q.limit {
  | Some(limit) => limit > 0.0 ? q.used /. limit : 0.0
  | _ => 0.0
  }
}

// Sort array by ratio ascending
let sortByRatio = (quotas: array<quotaData>): array<quotaData> => {
  let len = quotas->Belt.Array.length
  if len <= 1 {
    quotas
  } else {
    // Simple insertion sort
    let result = quotas->Belt.Array.copy
    let rec insertSort = (i: int): unit => {
      if i >= len {
        ()
      } else {
        let rec findPos = (j: int, keyRatio: float): int => {
          if j <= 0 {
            0
          } else {
            let prevRatio = ratio(result->Belt.Array.getExn(j - 1))
            if prevRatio <= keyRatio {
              j
            } else {
              let prev = result->Belt.Array.getExn(j - 1)
              result->Belt.Array.setExn(j, prev)
              findPos(j - 1, keyRatio)
            }
          }
        }
        let key = result->Belt.Array.getExn(i)
        let keyRatio = ratio(key)
        let pos = findPos(i, keyRatio)
        if pos != i {
          let rec shift = (j: int): unit => {
            if j >= pos {
              ()
            } else {
              let elem = result->Belt.Array.getExn(j)
              result->Belt.Array.setExn(j + 1, elem)
              shift(j - 1)
            }
          }
          shift(i - 1)
          result->Belt.Array.setExn(pos, key)
        }
        insertSort(i + 1)
      }
    }
    insertSort(1)
    result
  }
}

// -- strategies ----------------------------------------------------------------

let aggregateMax = (quotas: array<quotaData>): option<quotaData> => {
  if quotas->Belt.Array.length == 0 {
    None
  } else {
    let initial = quotas->Belt.Array.getExn(0)
    Some(
      quotas->Belt.Array.reduce(initial, (best, curr) => {
        ratio(curr) > ratio(best) ? curr : best
      }),
    )
  }
}

let aggregateMin = (quotas: array<quotaData>): option<quotaData> => {
  if quotas->Belt.Array.length == 0 {
    None
  } else {
    let initial = quotas->Belt.Array.getExn(0)
    Some(
      quotas->Belt.Array.reduce(initial, (best, curr) => {
        ratio(curr) < ratio(best) ? curr : best
      }),
    )
  }
}

let aggregateMean = (
  quotas: array<quotaData>,
  ~name: string="Aggregated",
  ~id: string="agg-mean",
): quotaData => {
  let len = quotas->Belt.Array.length->Belt.Float.fromInt
  let safeLen = len < 1.0 ? 1.0 : len
  let avgRatio = quotas->Belt.Array.reduce(0.0, (s, q) => s +. ratio(q)) /. safeLen
  {
    id,
    providerName: name,
    used: Math.round(avgRatio *. 100.0),
    limit: Some(100.0),
    unit: "%",
    reset: None,
    window: #rolling,
    info: None,
    modelId: None,
  }
}

let aggregateMedian = (
  quotas: array<quotaData>,
  ~name: string="Aggregated",
  ~id: string="agg-median",
): option<quotaData> => {
  if quotas->Belt.Array.length == 0 {
    None
  } else {
    let sorted = sortByRatio(quotas)
    let midIdx = (sorted->Belt.Array.length / 2)->Belt.Int.toFloat
    let mid = sorted->Belt.Array.getExn(midIdx->Belt.Int.fromFloat)
    Some({
      id,
      providerName: name,
      used: Math.round(ratio(mid) *. 100.0),
      limit: Some(100.0),
      unit: "%",
      reset: None,
      window: #rolling,
      info: None,
      modelId: None,
    })
  }
}

let aggregateMostCritical = (quotas: array<quotaData>, ettlMap: dict<float>): option<quotaData> => {
  if quotas->Belt.Array.length == 0 {
    None
  } else {
    let rec loop = (remaining: list<quotaData>, best: quotaData, minTime: float): (
      quotaData,
      float,
    ) => {
      switch remaining {
      | list{} => (best, minTime)
      | list{q, ...rest} =>
        let t = switch Dict.get(ettlMap, q.id) {
        | Some(v) => v
        | None => infinity
        }
        t < minTime ? loop(rest, q, t) : loop(rest, best, minTime)
      }
    }
    let first = quotas->Belt.Array.getExn(0)
    let (best, minTime) = loop(Belt.List.fromArray(quotas), first, infinity)
    minTime == infinity ? aggregateMax(quotas) : Some(best)
  }
}

// -- merge: defaults + user config -------------------------------------------

/**
 * Merge default aggregation groups with user-supplied groups.
 * User groups WIN on id collision (replace the default of the same id).
 * Defaults that have no user override are appended in original order.
 */
let mergeAggregationGroups = (
  userGroups: array<aggregationGroup>,
  defaultGroups: array<aggregationGroup>,
): array<aggregationGroup> => {
  let map = Dict.make()

  // Seed with defaults; user groups will overwrite on collision
  for i in 0 to defaultGroups->Belt.Array.length - 1 {
    let g = defaultGroups->Belt.Array.getExn(i)
    Dict.set(map, g.id, g)
  }

  // User wins on id collision
  for i in 0 to userGroups->Belt.Array.length - 1 {
    let g = userGroups->Belt.Array.getExn(i)
    Dict.set(map, g.id, g)
  }

  Dict.valuesToArray(map)
}

let aggregate = (
  quotas: array<quotaData>,
  strategy: aggregationStrategy,
  ~ettlMap: dict<float>=Dict.make(),
): option<quotaData> => {
  switch strategy {
  | #mostCritical => aggregateMostCritical(quotas, ettlMap)
  | #max => aggregateMax(quotas)
  | #min => aggregateMin(quotas)
  | #mean => Some(aggregateMean(quotas))
  | #median => aggregateMedian(quotas)
  }
}

// -- test helpers (pure domain, no I/O) ----------------------------------------

let makeAggregationGroup = (~id: string, ~providerId: string, ~strategy: aggregationStrategy) => {
  id,
  providerId,
  strategy,
}
