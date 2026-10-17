// src/rendering/SubscriptionListTests.res
// Behavior tests for the pure `-l/--list` renderer (S1/S3).
// Exact-output tests: the list is a user-facing contract, so every space counts.
// No env, no credentials, no process exit — the module is pure.
open RescriptTest

autoBoot := false

// ── Fixtures ─────────────────────────────────────────────────────────────────

let sixRows: array<SubscriptionList.row> = [
  {id: "openai", name: "OpenAI", credential: "opencode"},
  {id: "go", name: "opencode Go", credential: "pi"},
  {id: "zai", name: "z.ai Coding Plan", credential: "claude-code"},
  {id: "kimi", name: "Kimi / Moonshot", credential: "env"},
  {id: "minimax", name: "Minimax Coding Plan", credential: "config"},
  {id: "gemini", name: "Google Gemini", credential: "mmx"},
]

let oneRow: array<SubscriptionList.row> = [
  {id: "openai", name: "OpenAI", credential: "opencode"},
]

// 12 rows exercise the dynamic number-column width (1 → 2 chars) and keep
// every other column padded from its own content.
let twelveRows: array<SubscriptionList.row> = Array.fromInitializer(~length=12, i => {
  let n = Int.toString(i + 1)
  let row: SubscriptionList.row = {id: `p${n}`, name: `Provider ${n}`, credential: "opencode"}
  row
})

let footer = "Run `opencode-quotas -p <id>` to see usage for one subscription."

// ── Markdown / table rendering (S1) ──────────────────────────────────────────

test("S1: six rows render the exact markdown table", () => {
  let expected = [
    "## Available subscriptions (6)",
    "",
    "| # | ID      | Provider            | Credential  |",
    "|--:|---------|---------------------|-------------|",
    "| 1 | openai  | OpenAI              | opencode    |",
    "| 2 | go      | opencode Go         | pi          |",
    "| 3 | zai     | z.ai Coding Plan    | claude-code |",
    "| 4 | kimi    | Kimi / Moonshot     | env         |",
    "| 5 | minimax | Minimax Coding Plan | config      |",
    "| 6 | gemini  | Google Gemini       | mmx         |",
    "",
    footer,
  ]->Array.join("\n")
  assertion(
    ~message=`markdown should match exactly, got:\n${SubscriptionList.renderMarkdown(~rows=sixRows)}`,
    (a, b) => a == b,
    SubscriptionList.renderMarkdown(~rows=sixRows),
    expected,
  )
})

test("S1: one row still renders header, separator and hint", () => {
  let expected = [
    "## Available subscriptions (1)",
    "",
    "| # | ID     | Provider | Credential |",
    "|--:|--------|----------|------------|",
    "| 1 | openai | OpenAI   | opencode   |",
    "",
    footer,
  ]->Array.join("\n")
  assertion(
    ~message=`one-row markdown should match exactly, got:\n${SubscriptionList.renderMarkdown(~rows=oneRow)}`,
    (a, b) => a == b,
    SubscriptionList.renderMarkdown(~rows=oneRow),
    expected,
  )
})

test("S1: 12 rows right-align two-digit numbers and repad every column", () => {
  let expected = [
    "## Available subscriptions (12)",
    "",
    "|  # | ID  | Provider    | Credential |",
    "|---:|-----|-------------|------------|",
    "|  1 | p1  | Provider 1  | opencode   |",
    "|  2 | p2  | Provider 2  | opencode   |",
    "|  3 | p3  | Provider 3  | opencode   |",
    "|  4 | p4  | Provider 4  | opencode   |",
    "|  5 | p5  | Provider 5  | opencode   |",
    "|  6 | p6  | Provider 6  | opencode   |",
    "|  7 | p7  | Provider 7  | opencode   |",
    "|  8 | p8  | Provider 8  | opencode   |",
    "|  9 | p9  | Provider 9  | opencode   |",
    "| 10 | p10 | Provider 10 | opencode   |",
    "| 11 | p11 | Provider 11 | opencode   |",
    "| 12 | p12 | Provider 12 | opencode   |",
    "",
    footer,
  ]->Array.join("\n")
  assertion(
    ~message=`12-row markdown should match exactly, got:\n${SubscriptionList.renderMarkdown(~rows=twelveRows)}`,
    (a, b) => a == b,
    SubscriptionList.renderMarkdown(~rows=twelveRows),
    expected,
  )
})

test("S1: separator cells are content width + 2 and the first ends in a colon", () => {
  let lines = SubscriptionList.renderMarkdown(~rows=sixRows)->String.split("\n")
  let separator = Belt.Array.get(lines, 3)->Belt.Option.getWithDefault("")
  // Six rows: widths are 1, 7, 19, 11 → separator cells 3, 9, 21, 13.
  assertion(
    ~message=`separator row should be width+2 with a right-aligned first cell, got: ${separator}`,
    (a, b) => a == b,
    separator,
    "|--:|---------|---------------------|-------------|",
  )
})

// ── JSON rendering (S3) ──────────────────────────────────────────────────────

test("S3: JSON is a 2-space-indented array with only id, name, credential", () => {
  let rows: array<SubscriptionList.row> = [
    {id: "openai", name: "OpenAI", credential: "opencode"},
    {id: "zai", name: "z.ai Coding Plan", credential: "opencode"},
  ]
  let expected = [
    "[",
    "  {",
    "    \"id\": \"openai\",",
    "    \"name\": \"OpenAI\",",
    "    \"credential\": \"opencode\"",
    "  },",
    "  {",
    "    \"id\": \"zai\",",
    "    \"name\": \"z.ai Coding Plan\",",
    "    \"credential\": \"opencode\"",
    "  }",
    "]",
  ]->Array.join("\n")
  let actual = SubscriptionList.renderJson(~rows)
  assertion(
    ~message=`JSON should match exactly, got:\n${actual}`,
    (a, b) => a == b,
    actual,
    expected,
  )
  assertion(
    ~message="JSON must not carry the markdown header",
    (a, b) => a == b,
    String.includes(actual, "## Available subscriptions"),
    false,
  )
  assertion(
    ~message="JSON must not carry the markdown footer",
    (a, b) => a == b,
    String.includes(actual, footer),
    false,
  )
})

test("S3: JSON escapes content and keeps keys in id, name, credential order", () => {
  let rows: array<SubscriptionList.row> = [
    {id: "weird\"id", name: "Quote \"Provider\"", credential: "env"},
  ]
  let expected = [
    "[",
    "  {",
    "    \"id\": \"weird\\\"id\",",
    "    \"name\": \"Quote \\\"Provider\\\"\",",
    "    \"credential\": \"env\"",
    "  }",
    "]",
  ]->Array.join("\n")
  assertion(
    ~message=`escaped JSON should match exactly, got:\n${SubscriptionList.renderJson(~rows)}`,
    (a, b) => a == b,
    SubscriptionList.renderJson(~rows),
    expected,
  )
})

let () = runTests()
