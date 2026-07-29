// Pure domain: reset detection — ≥20% drop from peak triggers a reset signal.
open Types

let resetThresholdPercent = 20.0

let detectReset = (lastPoint: historyPoint, current: quotaData): bool => {
  switch lastPoint.limit {
  | None => false
  | Some(limit) =>
    limit <= 0.0
      ? false
      : {
          let drop = lastPoint.used -. current.used
          drop <= 0.0
            ? false
            : switch current.limit {
              | None => false
              | Some(cl) =>
                cl <= 0.0
                  ? false
                  : {
                      let threshold = resetThresholdPercent /. 100.0 *. cl
                      drop >= threshold
                    }

              }
        }

  }
}
