// ReportErrors.res — pure error formatting for CLI output
// Keeps I/O in Cli.res; these functions return (text, channel, exitCode).
// channel: #stdout | #stderr | #none

// ── Types ──────────────────────────────────────────────────────────────────────

type outputChannel = [#stdout | #stderr | #none]

type errorOutput = {
  text: string,
  channel: outputChannel,
  exitCode: int,
}

// ── Provider fetch errors → stderr + exit 0 ────────────────────────────────────

// Returns errorOutput for partial-result provider failures.
// When errorKeys (non-underscore keys) exist, formats them to stderr and exits 0.
// Returns #none channel when there are no such errors.
let formatProviderErrors = (errors: dict<string>): errorOutput => {
  let allKeys = errors->Dict.keysToArray
  let errorKeys = allKeys->Belt.Array.keep(k => k !== "_")

  if errorKeys->Array.length > 0 {
    let errorDict: dict<string> = Dict.make()
    let _ = errorKeys->Array.map(key => {
      let msg = switch errors->Dict.get(key) {
      | Some(m) => m
      | None => ""
      }
      let _ = Dict.set(errorDict, key, msg)
    })
    let text = `${Messages.formatProviderFetchErrors(errorDict)}\n`
    {text, channel: #stderr, exitCode: 0}
  } else {
    {text: "", channel: #none, exitCode: 0}
  }
}

// ── Fatal errors → stdout + exit 1 ────────────────────────────────────────────

// Returns errorOutput for fatal pipeline errors (underscore key).
// Returns #none channel when no fatal error exists.
let formatFatalError = (errors: dict<string>): errorOutput => {
  switch errors->Dict.get("_") {
  | Some(msg) => {text: `${msg}\n`, channel: #stdout, exitCode: 1}
  | None => {text: "", channel: #none, exitCode: 0}
  }
}
