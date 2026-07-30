// src/Infra/JsonFileHistory.res
// HistoryStore adapter with debounced writes and reset detection.

open Domain

type deps = {
  readFileSync: string => string,
  writeFileSync: (string, string) => unit,
  existsSync: string => bool,
  now: unit => float,
}

type fileShape = {history: dict<array<historyPoint>>}

// historyStore mirrors the port shape (defined locally since History.resi is interface-only)
type historyStore = {
  append: (string, historyPoint) => promise<unit>,
  getHistory: (string, float) => promise<array<historyPoint>>,
  prune: float => promise<unit>,
  resetDetected: (string, historyPoint, float, option<float>) => bool,
}

type store = {
  ...historyStore,
  flushNow: unit => unit,
}

// Public: build a HistoryStore instance with an attached flushNow
let make = (~debounceMs: float=5000.0, filePath: string, deps: deps): store => {
  let cache: ref<option<fileShape>> = ref(None)
  let pending: ref<option<float>> = ref(None)

  let load = (): fileShape => {
    switch cache.contents {
    | Some(c) => c
    | None =>
      let initial = if deps.existsSync(filePath) {
        let text = deps.readFileSync(filePath)
        let parsed: option<JSON.t> = try {
          Some(JSON.parseOrThrow(text))
        } catch {
        | _exn => None
        }
        switch parsed {
        | Some(json) =>
          // Typed JSON decoding: extract history dict and decode each provider's points
          let topDict = switch json {
          | JSON.Object(d) => d
          | _ => Dict.make()
          }
          let historyDict = switch Dict.get(topDict, "history") {
          | Some(JSON.Object(hd)) => hd
          | _ => Dict.make()
          }
          let result: dict<array<historyPoint>> = Dict.make()
          let keys = Dict.keysToArray(historyDict)
          let _ = keys->Array.forEach(key => {
            let pointsJson = switch Dict.get(historyDict, key) {
            | Some(JSON.Array(arr)) => arr
            | _ => []
            }
            let points = pointsJson->Array.map(p => {
              let pd = switch p {
              | JSON.Object(d) => d
              | _ => Dict.make()
              }
              let ts = switch Dict.get(pd, "timestamp") {
              | Some(JSON.Number(n)) => n
              | _ => 0.0
              }
              let used = switch Dict.get(pd, "used") {
              | Some(JSON.Number(n)) => n
              | _ => 0.0
              }
              let limit = switch Dict.get(pd, "limit") {
              | Some(JSON.Number(n)) => Some(n)
              | _ => None
              }
              ({timestamp: ts, used: used, limit: limit}: historyPoint)
            })
            let _ = Dict.set(result, key, points)
          })
          {history: result}
        | None => {history: Dict.make()}
        }
      } else {
        {history: Dict.make()}
      }
      cache := Some(initial)
      initial
    }
  }

  let save = (data: fileShape): unit => {
    // Convert fileShape to JSON string manually
    let keys = Dict.keysToArray(data.history)
    let pairs = keys->Belt.Array.map(k => {
      let v = switch Dict.get(data.history, k) {
      | Some(arr) => arr
      | None => []
      }
      let arrJson = "[" ++ v->Belt.Array.map(p => {
        let ts = Float.toString(p.timestamp)
        let used = Float.toString(p.used)
        let limitStr = switch p.limit {
        | Some(l) => ",\"limit\":" ++ Float.toString(l)
        | None => ""
        }
        "{\"timestamp\":" ++ ts ++ ",\"used\":" ++ used ++ limitStr ++ "}"
      })->Array.joinUnsafe(",") ++ "]"
      "\"" ++ k ++ "\":" ++ arrJson
    })
    let json = "{\"history\":{" ++ pairs->Array.joinUnsafe(",") ++ "}}"
    deps.writeFileSync(filePath, json)
  }

  let scheduleWrite = (data: fileShape): unit => {
    switch pending.contents {
    | Some(t) => Node.clearTimeoutId(t)
    | None => ()
    }
    let id = Node.setTimeoutMs(() => {
      save(data)
      pending := None
    }, debounceMs)
    pending := Some(id)
  }

  {
    append: (providerId: string, point: historyPoint): promise<unit> => {
      let data = load()
      let existing = switch Dict.get(data.history, providerId) {
      | Some(arr) => arr
      | None => []
      }
      // Get last element without Array.last
      let prev = switch existing->Belt.Array.length {
      | 0 => None
      | n => Belt.Array.get(existing, n - 1)
      }
      let resetHappened = switch prev {
      | Some(p) =>
        let quotaData: quotaData = {
          id: providerId,
          providerName: providerId,
          used: point.used,
          limit: point.limit,
          unit: "",
          reset: None,
          window: #daily,
          info: None,
          modelId: None,
        }
        Reset.detectReset(p, quotaData)
      | None => false
      }
      let updated = if resetHappened {
        [point]
      } else {
        Belt.Array.concat(existing, [point])
      }
      Dict.set(data.history, providerId, updated)
      cache := Some(data)
      scheduleWrite(data)
      Promise.resolve()
    },

    getHistory: (providerId: string, windowMs: float): promise<array<historyPoint>> => {
      let cutoff = deps.now() -. windowMs
      let data = load()
      let points = switch Dict.get(data.history, providerId) {
      | Some(arr) => arr
      | None => []
      }
      let result = points->Belt.Array.keep((p: historyPoint) => p.timestamp >= cutoff)
      Promise.resolve(result)
    },

    prune: (maxAgeMs: float): promise<unit> => {
      let cutoff = deps.now() -. maxAgeMs
      let data = load()
      let keys = Dict.keysToArray(data.history)
      keys->Belt.Array.forEach(pid => {
        let points = switch Dict.get(data.history, pid) {
        | Some(arr) => arr->Belt.Array.keep((p: historyPoint) => p.timestamp >= cutoff)
        | None => []
        }
        Dict.set(data.history, pid, points)
      })
      cache := Some(data)
      // prune saves immediately (per TS original behavior)
      save(data)
      Promise.resolve()
    },

    resetDetected: (providerId: string, prev: historyPoint, used: float, limit: option<float>): bool => {
      let quotaData: quotaData = {
        id: providerId,
        providerName: providerId,
        used: used,
        limit: limit,
        unit: "",
        reset: None,
        window: #daily,
        info: None,
        modelId: None,
      }
      Reset.detectReset(prev, quotaData)
    },

    flushNow: () => {
      switch pending.contents {
      | Some(t) => Node.clearTimeoutId(t)
      | None => ()
      }
      pending := None
      switch cache.contents {
      | Some(c) => save(c)
      | None => ()
      }
    },
  }
}
