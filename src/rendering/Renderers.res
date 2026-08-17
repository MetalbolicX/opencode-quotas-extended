// Table, JSON, and Markdown renderers.
open StatusBar
open TextClip

// Types

type translator = {
  t: (string, option<dict<string>>) => string,
}

// progressBarConfig matches ReportPipeline.progressBarConfig
type progressBarConfig = {
  width: option<float>,
  filledChar: option<string>,
  emptyChar: option<string>,
  color: option<bool>,
  gradients: option<bool>,
}

type renderContext = {
  mode: Domain.renderMode,
  color: option<string>,
  compact: option<bool>,
  progressBar: option<progressBarConfig>,
  terminalWidth: option<float>,
  header: option<{brand: string, plan: option<string>}>,
  t: translator,
}

type renderer = {
  render: (array<Domain.quotaData>, renderContext) => string,
}

// Helpers

let fmtPct = (r: option<float>): string => {
  switch r {
  | None => "INF"
  | Some(r') => `${Float.toString(Math.round(r' *. 100.0))}%`
  }
}

// fmtReset formats a reset date into a human-readable string.
// reset is always option<Date.t> (providers now build Domain.quotaData directly).
let fmtReset = (d: option<Date.t>): string => {
  switch d {
  | None => "-"
  | Some(dateObj) =>
    let millis = Date.getTime(dateObj)
    if millis <= 0.0 {
      "now"
    } else {
      let now = Date.now()
      let diff = millis -. now
      if diff <= 0.0 {
        "now"
      } else {
        let m = Math.floor(diff /. 60000.0)
        if m < 60.0 {
          `${Float.toString(Math.round(m))}m`
        } else {
          let h = Math.floor(m /. 60.0)
          if h < 24.0 {
            `${Float.toString(Math.round(h))}h`
          } else {
            `${Float.toString(Math.round(h /. 24.0))}d`
          }
        }
      }
    }
  }
}

let humanize = (n: float): string => {
  if n >= 1_000_000.0 {
    let v = n /. 1_000_000.0
    let s = Float.toString(v)
    let idx = String.indexOf(s, ".")
    if idx === -1 {
      `${s}M`
    } else {
      let extra = switch String.get(s, idx + 1) {
      | Some("0") => 1
      | Some(_) => 2
      | None => 2
      }
      let endIdx = idx + extra
      `${String.substring(s, ~start=0, ~end=endIdx)}M`
    }
  } else if n >= 1_000.0 {
    let v = n /. 1_000.0
    let s = Float.toString(v)
    let idx = String.indexOf(s, ".")
    if idx === -1 {
      `${s}K`
    } else {
      let extra = switch String.get(s, idx + 1) {
      | Some("0") => 1
      | Some(_) => 2
      | None => 2
      }
      let endIdx = idx + extra
      `${String.substring(s, ~start=0, ~end=endIdx)}K`
    }
  } else {
    Float.toString(n)
  }
}

let usageText = (q: Domain.quotaData, ratio: option<float>): string => {
  switch q.unit {
  | "%" =>
    switch q.limit {
    | None => "unlimited"
    | Some(_) =>
      let pct = Math.round(Belt.Option.getWithDefault(ratio, 0.0) *. 100.0)
      `${Float.toString(pct)}% used`
    }
  | "requests" =>
    switch q.limit {
    | None => "no limit"
    | Some(lim) => `${Float.toString(q.used)} / ${Float.toString(lim)} requests`
    }
  | "tokens" =>
    switch q.limit {
    | None => "no limit"
    | Some(lim) => `${humanize(q.used)} / ${humanize(lim)} tokens`
    }
  | "credits" =>
    `balance: ${Float.toString(q.used)}`
  | _ =>
    switch q.limit {
    | None => "no limit"
    | Some(lim) => `${Float.toString(q.used)} / ${Float.toString(lim)} ${q.unit}`
    }
  }
}

let frameWidth = (~terminalWidth: option<float>=?): int => {
  let inner = switch terminalWidth {
  | Some(tw) =>
    let inner = Math.Int.max(Math.Int.min(Belt.Float.toInt(tw), 80), 60)
    let outOfRange = tw < 60.0 || tw > 80.0
    inner + (if outOfRange { 2 } else { 4 })
  | None => 80
  }
  inner + 4
}

// ─── Window label helper ──────────────────────────────────────────────────────
// Shared pure windowType→string conversion used by both table and JSON renderers.
// All providers produce Domain.quotaData with camelCase windowType variants.
let windowLabel = (w: Domain.windowType): string => {
  switch w {
  | #rolling5h => "rolling-5h"
  | #rollingMcp => "rolling-mcp"
  | #rollingTokens => "rolling-tokens"
  | #rollingWeekly => "rolling-weekly"
  | #rolling1h => "rolling-1h"
  | #daily => "daily"
  | #monthly => "monthly"
  | #rolling => "rolling"
  }
}

let windowLabelText = (q: Domain.quotaData): string => windowLabel(q.window)

// Constants

let info_W: int = 24
let bar_W: int = 13
let usage_W: int = 27
let reset_W: int = 6
let ettl_W: int = 6

// Status glyph map

let statusGlyph: dict<string> = Dict.fromArray([
  ("OK", "\u2713"),
  ("WRN", "!"),
  ("ERR", "\u2715"),
  ("UNK", "?"),
])

// Default progress bar options

let defaultBarOpts: progressBarConfig = {
  width: Some(10.0),
  filledChar: Some("\u2588"),
  emptyChar: Some("."),
  color: Some(false),
  gradients: Some(false),
}

// Table renderer

let tableRenderer: renderer = {
  render: (quotas, ctx) => {
    let color = ctx.color
    let compact = ctx.compact
    let tw = ctx.terminalWidth
    let hdr = ctx.header
    let barOpts: progressBarConfig = switch ctx.progressBar {
    | Some(v) => v
    | None => defaultBarOpts
    }
    let w = frameWidth(~terminalWidth=?tw)
    let innerW = w - 4

    // ASCII frame border
    let rec repeat = (n, acc) =>
      if n <= 0 { acc } else { repeat(n - 1, acc ++ "-") }
    let topBot = `+${repeat(w - 2, "")}+`

    // Header row
    let headerRow = switch hdr {
    | Some(h) =>
      let wl = switch quotas->Belt.Array.get(0) {
      | Some(q) => windowLabelText(q)
      | None => ""
      }
      let parts = switch (h.brand, h.plan, wl !== "") {
      | (brand, None, false) => [brand]
      | (brand, Some(plan), false) => [brand, plan]
      | (brand, None, true) => [brand, wl]
      | (brand, Some(plan), true) => [brand, plan, wl]
      }
      let headerText = parts->Array.joinUnsafe(" . ")
      `| ${clip(~width=innerW, headerText)} |`
    | None => ""
    }

    let useColor = color !== None

    let statusCodeStr = (code: StatusBar.statusCode): string => {
      switch code {
      | OK => "OK"
      | WRN => "WRN"
      | ERR => "ERR"
      | UNK => "UNK"
      }
    }

    let rows = quotas->Belt.Array.map(q => {
      let s = StatusBar.getStatus(q.used, q.limit)

      // info cell
      let infoCell = clip(~width=info_W, Belt.Option.getWithDefault(q.info, ""))

      // bar
      let isToken = q.unit === "tokens"
      let barCell = if isToken {
        " "->String.repeat(bar_W)
      } else {
        let ratio = switch s.ratio {
        | Some(r') => r'
        | None => 0.0
        }
        let barColorName: option<string> = if useColor { color } else { None }
        let barColorSplit: option<string> = if useColor { Some("filled") } else { None }
        let mergedOpts: StatusBar.barOptions = {
          width: barOpts.width,
          filledChar: barOpts.filledChar,
          emptyChar: barOpts.emptyChar,
          colorName: barColorName,
          framed: Some(true),
          colorSplit: barColorSplit,
        }
        StatusBar.renderBar(ratio, ~opts=mergedOpts)
      }

      // usage
      let rawUsage = usageText(q, s.ratio)
      let glyphStr = switch Dict.get(statusGlyph, statusCodeStr(s.code)) {
      | Some(g) => g
      | None => "?"
      }
      let usageWithGlyph = if isToken { `${glyphStr} ${rawUsage}` } else { rawUsage }
      let usageCell = clip(~width=usage_W, usageWithGlyph)

      // reset
      let resetCell = clip(~width=reset_W, fmtReset(q.reset))
      // ettl
      let ettlCell = switch compact {
      | Some(true) => ""
      | _ => clip(~width=ettl_W, "-")
      }

      let rowText = switch compact {
      | Some(true) => `${infoCell} ${barCell} ${usageCell}`
      | _ => `${infoCell} ${barCell} ${usageCell} ${resetCell} ${ettlCell}`
      }
      `| ${rowText} |`
    })

    let lines = [topBot]
    if headerRow !== "" {
      lines->Belt.Array.push(headerRow)->ignore
    }
    rows->Belt.Array.forEach(row => lines->Belt.Array.push(row)->ignore)
    lines->Belt.Array.push(topBot)->ignore
    lines->Array.joinUnsafe("\n")
  },
}

// JSON renderer

let windowToStr = (w: Domain.windowType): string => windowLabel(w)

let jsonRenderer: renderer = {
  render: (quotas, _ctx) => {
    let items = quotas->Belt.Array.map(q => {
      let s = StatusBar.getStatus(q.used, q.limit)
      let statusStr = switch s.code {
      | OK => "OK"
      | WRN => "WRN"
      | ERR => "ERR"
      | UNK => "UNK"
      }
      let obj: dict<JSON.t> = Dict.make()
      Dict.set(obj, "id", JSON.Encode.string(q.id))
      Dict.set(obj, "provider", JSON.Encode.string(q.providerName))
      Dict.set(obj, "used", JSON.Encode.float(q.used))
      switch q.limit {
      | Some(l) => Dict.set(obj, "limit", JSON.Encode.float(l))
      | None => Dict.set(obj, "limit", JSON.Encode.null)
      }
      Dict.set(obj, "unit", JSON.Encode.string(q.unit))
      Dict.set(obj, "status", JSON.Encode.string(statusStr))
      switch s.ratio {
      | Some(r) => Dict.set(obj, "ratio", JSON.Encode.float(r))
      | None => Dict.set(obj, "ratio", JSON.Encode.null)
      }
      switch q.reset {
      | Some(dateObj) =>
        let millis = Date.getTime(dateObj)
        Dict.set(obj, "reset", JSON.Encode.string(millis->Float.toString))
      | None => Dict.set(obj, "reset", JSON.Encode.null)
      }
      Dict.set(obj, "window", JSON.Encode.string(windowToStr(q.window)))
      obj
    })
    let iso = Date.now()->Float.toString
    let root: dict<JSON.t> = Dict.make()
    Dict.set(root, "fetchedAt", JSON.Encode.string(iso))
    let jsonItems = items->Belt.Array.map(item => JSON.Encode.object(item))
    Dict.set(root, "quotas", JSON.Encode.array(jsonItems))
    JSON.stringify(JSON.Encode.object(root), ~space=2)
  },
}

// Markdown renderer

let markdownRenderer: renderer = {
  render: (quotas, ctx) => {
    let t = ctx.t
    let rows = quotas->Belt.Array.map(q => {
      let s = StatusBar.getStatus(q.used, q.limit)
      let statusStr = switch s.code {
      | OK => "OK"
      | WRN => "WRN"
      | ERR => "ERR"
      | UNK => "UNK"
      }
      `| ${q.providerName} | ${statusStr} | ${fmtPct(s.ratio)} | ${fmtReset(q.reset)} | - |`
    })
    [
      `| ${t.t("header.name", None)} | ${t.t("header.status", None)} | ${t.t("header.percent", None)} | ${t.t("header.reset", None)} | ${t.t("header.ettl", None)} |`,
      "|------|--------|-------|-------|-------|",
      ...rows,
    ]->Array.joinUnsafe("\n")
  },
}

// Renderer selection

let selectRenderer = (mode: Domain.renderMode): renderer => {
  switch mode {
  | #table => tableRenderer
  | #json => jsonRenderer
  | #markdown => markdownRenderer
  }
}
