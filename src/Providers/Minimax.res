// src/Providers/Minimax.res
// Minimax Coding Plan provider — CLI-based (no HTTP endpoint).
// Credentials: key stored in auth.json under "minimax-coding-plan".
// Uses mmx CLI subprocess.

open SemanticLabels

// --- execSync external (local, avoids any Node module shadowing) -----------

type execOpts = {
  encoding: string,
  timeout: int,
  stdio: string,
}

@module("node:child_process")
external runExec: (string, execOpts) => string = "execSync"

// --- Helpers -----------------------------------------------------------------

// Converts any JSON value to option<float>, supporting numeric strings.
let toNum = (json: JSON.t): option<float> => {
  switch json {
  | JSON.Number(n) => Some(n)
  | JSON.String(s) =>
    let trimmed = String.trim(s)
    switch trimmed {
    | "" => None
    | _ => Float.fromString(trimmed)
    }
  | _ => None
  }
}

// Builds a reset Date by adding `remainsMs` (ms) to the current time.
// Returns None when the value is missing or non-positive. The mmx CLI returns
// `remains_time` / `weekly_remains_time` in ms relative to "now", which is
// clock-independent and avoids the precision pitfalls of absolute timestamps.
let resetFromRemainsMs = (remainsMs: option<float>): option<Date.t> => {
  switch remainsMs {
  | Some(ms) =>
    if ms > 0.0 {
      Some(Date.fromTime(Date.now() +. ms))
    } else {
      None
    }
  | None => None
  }
}

// Extracts JSON blob from mmx stdout — the JSON starts at the opening `{`
// of the unique "model_remains" key (which appears after a human-readable table).
let extractJson = (out: string): option<string> => {
  let idx = out->String.indexOf("\"model_remains\"")
  if idx < 0 {
    None
  } else {
    let start = {
      // Search for '{' within the prefix [0, idx] of out
      let prefix = String.slice(out, ~start=0, ~end=idx + 1)
      let pos = Js.String.lastIndexOf("{", prefix)
      if pos >= 0 { pos } else { -1 }
    }
    if start < 0 {
      None
    } else {
      Some(out->String.slice(~start))
    }
  }
}

// Parse mmx quota JSON into QuotaData array.
let parseMinimaxCli = (out: string): array<Domain.quotaData> => {
  let jsonText = switch extractJson(out) {
  | Some(t) => t
  | None => ""
  }
  if jsonText === "" {
    []
  } else {
    let json: JSON.t = JSON.parseOrThrow(jsonText)
    switch json {
    | JSON.Object(dict) =>
      let remains = switch Dict.get(dict, "model_remains") {
      | Some(JSON.Array(arr)) => arr
      | _ => []
      }
      let entries: array<Domain.quotaData> = []
      // Filter general + video model entries
      let general = remains->Array.filter(m => {
        switch m {
        | JSON.Object(mdict) =>
          switch Dict.get(mdict, "model_name") {
          | Some(JSON.String("general")) => true
          | _ => false
          }
        | _ => false
        }
      })
      let video = remains->Array.filter(m => {
        switch m {
        | JSON.Object(mdict) =>
          switch Dict.get(mdict, "model_name") {
          | Some(JSON.String("video")) => true
          | _ => false
          }
        | _ => false
        }
      })
      // General entries: 5h interval + weekly
      let _ = general->Array.forEach(m => {
        switch m {
        | JSON.Object(mdict) =>
          let intervalPct = toNum(
            switch Dict.get(mdict, "current_interval_remaining_percent") {
            | Some(v) => v
            | _ => JSON.Number(0.0)
            },
          )->Belt.Option.getWithDefault(0.0)
          let intervalConcept = enrichQuotaLabel(
            "minimax",
            {
              type_: None,
              unit: None,
              number: None,
              modelName: Some("general"),
              weekly: Some(false),
              openaiVariant: None,
              geminiModel: None,
            },
          )
          let intervalReset = resetFromRemainsMs(
            toNum(
              switch Dict.get(mdict, "remains_time") {
              | Some(v) => v
              | _ => JSON.Number(0.0)
              },
            ),
          )
          let _ = Belt.Array.push(
            entries,
            {
              id: "minimax-general-5h",
              providerName: buildProviderName("Minimax", intervalConcept.concept),
              used: 100.0 -. intervalPct,
              limit: Some(100.0),
              unit: "%",
              reset: intervalReset,
              window: #rolling5h,
              info: Some(intervalConcept.label),
              modelId: None,
            },
          )
          let weeklyPct = toNum(
            switch Dict.get(mdict, "current_weekly_remaining_percent") {
            | Some(v) => v
            | _ => JSON.Number(0.0)
            },
          )->Belt.Option.getWithDefault(0.0)
          let weeklyConcept = enrichQuotaLabel(
            "minimax",
            {
              type_: None,
              unit: None,
              number: None,
              modelName: Some("general"),
              weekly: Some(true),
              openaiVariant: None,
              geminiModel: None,
            },
          )
          let weeklyReset = resetFromRemainsMs(
            toNum(
              switch Dict.get(mdict, "weekly_remains_time") {
              | Some(v) => v
              | _ => JSON.Number(0.0)
              },
            ),
          )
          let _ = Belt.Array.push(
            entries,
            {
              id: "minimax-general-weekly",
              providerName: buildProviderName("Minimax", weeklyConcept.concept),
              used: 100.0 -. weeklyPct,
              limit: Some(100.0),
              unit: "%",
              reset: weeklyReset,
              window: #rollingWeekly,
              info: Some(weeklyConcept.label),
              modelId: None,
            },
          )
        | _ => ()
        }
      })
      // Video entry: interval only (no weekly video)
      let _ = video->Array.forEach(m => {
        switch m {
        | JSON.Object(mdict) =>
          let total = toNum(
            switch Dict.get(mdict, "current_interval_total_count") {
            | Some(v) => v
            | _ => JSON.Number(0.0)
            },
          )->Belt.Option.getWithDefault(0.0)
          let used = toNum(
            switch Dict.get(mdict, "current_interval_usage_count") {
            | Some(v) => v
            | _ => JSON.Number(0.0)
            },
          )->Belt.Option.getWithDefault(0.0)
          let videoPct = total > 0.0 ? Math.round(used /. total *. 100.0) : 0.0
          let concept = enrichQuotaLabel(
            "minimax",
            {
              type_: None,
              unit: None,
              number: None,
              modelName: Some("video"),
              weekly: Some(false),
              openaiVariant: None,
              geminiModel: None,
            },
          )
          let videoReset = resetFromRemainsMs(
            toNum(
              switch Dict.get(mdict, "remains_time") {
              | Some(v) => v
              | _ => JSON.Number(0.0)
              },
            ),
          )
          let _ = Belt.Array.push(
            entries,
            {
              id: "minimax-video-interval",
              providerName: buildProviderName("Minimax", concept.concept),
              used: videoPct,
              limit: Some(100.0),
              unit: "%",
              reset: videoReset,
              window: #daily,
              info: Some(concept.label),
              modelId: None,
            },
          )
        | _ => ()
        }
      })
      entries
    | _ => []
    }
  }
}

// Pre-check that mmx binary exists in PATH.
// Throws if not found; caller catches and returns [].
let assertMmxBinary = (): string => {
  let opts: execOpts = {encoding: "utf8", timeout: 5000, stdio: "pipe"}
  runExec("which mmx", opts)
}

// Non-throwing binary check (used by isAvailable).
let hasMmxBinary = (): bool => {
  try {
    let _ = runExec("which mmx", {encoding: "utf8", timeout: 5000, stdio: "pipe"})
    true
  } catch {
  | _ => false
  }
}

// Run `mmx quota show` against any existing session. None on failure/empty.
// Does NOT check the binary — callers ensure it (or accept None).
let tryQuotaShow = (opts: execOpts): option<string> => {
  try {
    Some(String.trim(runExec("mmx quota show --output json 2>/dev/null", opts)))
  } catch {
  | _ => None
  }
}

// Parse session stdout into rows. None when output is missing, unparseable,
// or yields zero rows. (parseMinimaxCli returns [] for a missing model_remains
// key, and throws on malformed JSON — both collapse to None here.)
let parseSessionRows = (output: option<string>): option<array<Domain.quotaData>> => {
  switch output {
  | None => None
  | Some(out) =>
    try {
      let rows = parseMinimaxCli(out)
      Array.length(rows) > 0 ? Some(rows) : None
    } catch {
    | _ => None
    }
  }
}

// Pure decision: given parsed session rows and an optional key, pick the step.
// Session rows present -> reuse them (no login). Otherwise use the key, or give up.
type fetchStep =
  | UseSession(array<Domain.quotaData>)
  | LoginWithKey(string)
  | GiveUp

let decideFetchStep = (
  sessionRows: option<array<Domain.quotaData>>,
  key: option<string>,
): fetchStep => {
  switch sessionRows {
  | Some(rows) => UseSession(rows)
  | None =>
    switch key {
    | Some(k) => LoginWithKey(k)
    | None => GiveUp
    }
  }
}

// --- Provider ----------------------------------------------------------------

let createMinimaxProvider = (): Provider.quotaProvider => {
  id: "minimax",
  displayName: "Minimax Coding Plan",
  category: "subscription",
  authStrategy: #api,
  isAvailable: () =>
    CredentialResolver.resolve("minimax-coding-plan")->Promise.then(opt => {
      switch opt {
      | Some(_) => Promise.resolve(true)   // stored credential present
      | None =>
        // No stored credential — still available if mmx is installed AND already
        // authenticated (reuse of an existing session).
        Promise.resolve(hasMmxBinary() && parseSessionRows(
          tryQuotaShow({encoding: "utf8", timeout: 15000, stdio: "pipe"})
        )->Belt.Option.isSome)
      }
    })->Promise.catch(. _err => Promise.resolve(false)),
  fetchQuotas: () => {
    CredentialResolver.resolve("minimax-coding-plan")->Promise.then(opt => {
      // Extract optional API key from whatever credential variant resolved.
      let key = switch opt {
      | Some(Credential.Api(c)) => Some(c.key)
      | Some(Credential.Wellknown(c)) => Some(c.key)
      | Some(Credential.Env(c)) => Node.processEnv->Dict.get(c.envVar)
      | Some(Credential.OAuth(_)) | None => None
      }
      // mmx binary missing is a real provider error -> propagate (reject).
      let _ = assertMmxBinary()
      let execOpts: execOpts = {encoding: "utf8", timeout: 30000, stdio: "pipe"}
      // Step 1: reuse any existing mmx session (NO login round-trip).
      let sessionRows = parseSessionRows(tryQuotaShow(execOpts))
      switch decideFetchStep(sessionRows, key) {
      | UseSession(rows) => Promise.resolve(rows)
      | LoginWithKey(k) =>
        // Fallback: authenticate with the stored key, then fetch.
        // Failures here MUST throw and propagate as provider errors (invariant).
        let _ = runExec("mmx auth login --api-key '" ++ k ++ "' 2>/dev/null", execOpts)
        let stdout = String.trim(runExec("mmx quota show --output json 2>/dev/null", execOpts))
        Promise.resolve(parseMinimaxCli(stdout))
      | GiveUp => Promise.resolve([])   // no key and no usable session
      }
    })
  },
}
