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

// --- Local type declarations (mirrors port interfaces) -----------------------

type authStrategy = [#api | #oauth | #wellknown | #env]

type quotaProvider = {
  id: string,
  displayName: string,
  category: string,
  authStrategy: authStrategy,
  isAvailable: unit => promise<bool>,
  fetchQuotas: unit => promise<array<Domain.quotaData>>,
}

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

// Extracts JSON blob from mmx stdout — the JSON starts at the opening `{`
// of the unique "model_remains" key (which appears after a human-readable table).
let extractJson = (out: string): option<string> => {
  let idx = out->String.indexOf("\"model_remains\"")
  if idx < 0 {
    None
  } else {
    let start = %raw("(s, idx) => s.lastIndexOf('{', idx)")(out, idx)
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
          let _ = Belt.Array.push(
            entries,
            {
              id: "minimax-general-5h",
              providerName: buildProviderName("Minimax", intervalConcept.concept),
              used: 100.0 -. intervalPct,
              limit: Some(100.0),
              unit: "%",
              reset: None,
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
          let _ = Belt.Array.push(
            entries,
            {
              id: "minimax-general-weekly",
              providerName: buildProviderName("Minimax", weeklyConcept.concept),
              used: 100.0 -. weeklyPct,
              limit: Some(100.0),
              unit: "%",
              reset: None,
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
          let _ = Belt.Array.push(
            entries,
            {
              id: "minimax-video-interval",
              providerName: buildProviderName("Minimax", concept.concept),
              used: videoPct,
              limit: Some(100.0),
              unit: "%",
              reset: None,
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

// --- Provider ----------------------------------------------------------------

let createMinimaxProvider = (): quotaProvider => {
  id: "minimax",
  displayName: "Minimax Coding Plan",
  category: "subscription",
  authStrategy: #api,
  isAvailable: () =>
    CredentialResolver.resolve("minimax-coding-plan")->Promise.then(opt =>
      Promise.resolve(Belt.Option.isSome(opt))
    ),
  fetchQuotas: () => {
    CredentialResolver.resolve("minimax-coding-plan")->Promise.then(opt => {
      switch opt {
      | None => Promise.resolve([])
      | Some(cred) =>
        let key = switch cred {
        | Credential.Api(c) => Some(c.key)
        | Credential.Wellknown(c) => Some(c.key)
        | Credential.Env(c) => Node.processEnv->Dict.get(c.envVar)
        | Credential.OAuth(_) => None
        }
        switch key {
        | None => Promise.resolve([])
        | Some(k) =>
          try {
            let _ = assertMmxBinary()
            let execOpts: execOpts = {encoding: "utf8", timeout: 30000, stdio: "pipe"}
            // Step 1: auth (key wrapped in quotes for shell safety)
            let _ = runExec("mmx auth login --api-key '" ++ k ++ "' 2>/dev/null", execOpts)
            // Step 2: get quota
            let stdout = String.trim(runExec("mmx quota show --output json 2>/dev/null", execOpts))
            Promise.resolve(parseMinimaxCli(stdout))
          } catch {
          | _ => Promise.resolve([])
          }
        }
      }
    })
  },
}
