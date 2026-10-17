// src/rendering/SubscriptionList.res
// Pure renderer for the `-l/--list` subscription list (S1/S3).
// Zero I/O: the CLI collects rows, renders here, and prints once.
// `credential` is always a source label (opencode | pi | claude-code | env |
// config | mmx) — no credential material ever reaches this module.

type row = {id: string, name: string, credential: string}

let headers = ["#", "ID", "Provider", "Credential"]

// ── Padding helpers ──────────────────────────────────────────────────────────

let pad = (text: string, width: int, ~right: bool): string => {
  let missing = width - String.length(text)
  if missing <= 0 {
    text
  } else {
    let padding = String.repeat(" ", missing)
    right ? padding ++ text : text ++ padding
  }
}

// ── Column widths (dynamic: content + header, never a fixed layout) ──────────

let cellAt = (cells: array<string>, column: int): string =>
  switch Belt.Array.get(cells, column) {
  | Some(cell) => cell
  | None => ""
  }

let widen = (widths: array<int>, cells: array<string>): array<int> =>
  widths->Array.mapWithIndex((width, column) => {
    let len = String.length(cellAt(cells, column))
    len > width ? len : width
  })

let columnWidths = (rows: array<row>): array<int> => {
  let initial = headers->Array.map(width => width->String.length)
  rows->Array.mapWithIndex((row, index) => [Int.toString(index + 1), row.id, row.name, row.credential])
  ->Array.reduce(initial, (widths, cells) => widen(widths, cells))
}

// ── Markdown table (S1) ──────────────────────────────────────────────────────

// Every cell is `${space}${content}${space}`; the number column is right-aligned
// (its cells are left-padded, its separator ends in a colon).
let tableLine = (cells: array<string>, widths: array<int>): string => {
  let padded = cells->Array.mapWithIndex((cell, column) => {
    let width = switch Belt.Array.get(widths, column) {
    | Some(w) => w
    | None => String.length(cell)
    }
    pad(cell, width, ~right=column === 0)
  })
  "| " ++ padded->Array.join(" | ") ++ " |"
}

// Separator cell = content width + 2 (the same two outside spaces the content
// rows use); the first cell keeps the width and gains the right-align colon.
let separatorLine = (widths: array<int>): string => {
  let cells = widths->Array.mapWithIndex((width, column) =>
    column === 0
      ? String.repeat("-", width + 1) ++ ":"
      : String.repeat("-", width + 2)
  )
  "|" ++ cells->Array.join("|") ++ "|"
}

let renderMarkdown = (~rows: array<row>): string => {
  let widths = columnWidths(rows)
  let body = rows->Array.mapWithIndex((row, index) =>
    tableLine([Int.toString(index + 1), row.id, row.name, row.credential], widths)
  )
  let title = `## Available subscriptions (${Int.toString(rows->Array.length)})`
  let hint = "Run `opencode-quotas -p <id>` to see usage for one subscription."
  Array.concat(
    Array.concat([title, "", tableLine(headers, widths), separatorLine(widths)], body),
    ["", hint],
  )->Array.join("\n")
}

// ── JSON (S3) ────────────────────────────────────────────────────────────────

let rowJson = (row: row): JSON.t =>
  JSON.Object(
    Dict.fromArray([
      ("id", JSON.String(row.id)),
      ("name", JSON.String(row.name)),
      ("credential", JSON.String(row.credential)),
    ]),
  )

let renderJson = (~rows: array<row>): string =>
  JSON.stringify(JSON.Array(rows->Array.map(rowJson)), ~space=2)
