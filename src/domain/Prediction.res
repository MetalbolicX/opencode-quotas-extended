// Pure domain: zero I/O. Dual-window linear regression ETTL.
open Types

type predictionParams = {
  windowMinutes: option<float>,
  shortWindowMinutes: option<float>,
  now: option<float>,
  windowInfo: option<string>,
}

let longWindowMinutesDefault = 60.0
let shortWindowMinutesDefault = 5.0
let idleTimeoutMs = 5.0 *. 60.0 *. 1000.0
let shortWindowFallbackRatio = 0.15

let floatMax = (a: float, b: float): float => a > b ? a : b

let slope = (history: array<historyPoint>): float => {
  let len = history->Belt.Array.length
  len < 2
    ? 0.0
    : {
        let first = history->Belt.Array.getExn(0)
        let firstTs = first.timestamp
        let rec loop = (i: int, sumX: float, sumY: float, sumXY: float, sumX2: float): (float, float, float, float) => {
          i >= len
            ? (sumX, sumY, sumXY, sumX2)
            : {
                let p = history->Belt.Array.getExn(i)
                let x = p.timestamp -. firstTs
                let y = p.used
                loop(i + 1, sumX +. x, sumY +. y, sumXY +. x *. y, sumX2 +. x *. x)
              }
        }
        let (sumX, sumY, sumXY, sumX2) = loop(0, 0.0, 0.0, 0.0, 0.0)
        let denom = (len->Belt.Float.fromInt) *. sumX2 -. sumX *. sumX
        denom == 0.0
          ? 0.0
          : ((len->Belt.Float.fromInt) *. sumXY -. sumX *. sumY) /. denom
      }
}

let isLongTermWindow = (windowInfo: option<string>): bool => {
  switch windowInfo {
  | None => false
  | Some(info) => Js.Re.test_(%re("/week|month|\d+d/i"), info)
  }
}

let predictTimeToLimit = (
  history: array<historyPoint>,
  ~params: option<predictionParams>=?,
): float => {
  let p = switch params {
  | Some(p) => p
  | None => { windowMinutes: None, shortWindowMinutes: None, now: None, windowInfo: None }
  }
  let longWindowMs = (p.windowMinutes->Belt.Option.getWithDefault(longWindowMinutesDefault)) *. 60.0 *. 1000.0
  let shortWindowMs = (p.shortWindowMinutes->Belt.Option.getWithDefault(shortWindowMinutesDefault)) *. 60.0 *. 1000.0
  // Js.Date.now() returns milliseconds as float
  let now = p.now->Belt.Option.getWithDefault(Js.Date.now())

  history->Belt.Array.length < 2
    ? infinity
    : {
        let lastIdx = history->Belt.Array.length - 1
        let lastPoint = history->Belt.Array.getExn(lastIdx)
        (now -. lastPoint.timestamp) > idleTimeoutMs
          ? infinity
          : {
              let windowed = history->Belt.Array.keep(pp => (pp.timestamp >= (now -. longWindowMs)))
              let mLong = slope(windowed)
              mLong <= 0.0
                ? infinity
                : {
                    let m = ! isLongTermWindow(p.windowInfo)
                      ? {
                          let shortHistory = windowed->Belt.Array.keep(pp => (pp.timestamp >= (now -. shortWindowMs)))
                          let effective = shortHistory->Belt.Array.length >= 2
                            ? shortHistory
                            : {
                                let fallbackLen = Js.Math.round((history->Belt.Array.length->Belt.Float.fromInt) *. shortWindowFallbackRatio)
                                let safeLen = fallbackLen < 2.0 ? 2.0 : fallbackLen
                                let startIdx = history->Belt.Array.length - (safeLen->Belt.Int.fromFloat)
                                history->Belt.Array.slice(~offset=startIdx, ~len=(safeLen->Belt.Int.fromFloat))
                              }
                          let mShort = slope(effective)
                          floatMax(mLong, mShort)
                        }
                      : mLong
                    m <= 0.0
                      ? infinity
                      : {
                          switch lastPoint.limit {
                          | None => infinity
                          | Some(limit) =>
                            limit <= 0.0
                              ? infinity
                              : {
                                  let remaining = limit -. lastPoint.used
                                  remaining <= 0.0
                                    ? 0.0
                                    : floatMax(0.0, (remaining /. m) -. (now -. lastPoint.timestamp))
                                }
                          | _ => infinity
                          }
                        }
                  }
            }
      }
}
