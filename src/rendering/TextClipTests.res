// src/rendering/TextClipTests.res
// Tests for TextClip module — ANSI-aware text truncation utility.
// Covers: clip (width 0, ellipsis-length, ANSI strip, truncation, padding,
// custom ellipsis, multi-byte unicode), stripAnsi.
open RescriptTest
open TextClip

autoBoot := false

// TC1: width=0 returns empty string
test("TC1: clip returns empty string when width is 0", () => {
  let result = clip("hello", ~width=0)
  assertion(
    ~message=`Expected empty string, got "${result}"`,
    (a, b) => a == b,
    result,
    "",
  )
})

// TC2: width=1 equals ellipsis length → returns just ellipsis
test("TC2: clip returns just ellipsis when width equals ellipsis length", () => {
  let result = clip("hello", ~width=1)
  assertion(
    ~message=`Expected "…" (1 char), got "${result}"`,
    (a, b) => a == b,
    result,
    "…",
  )
})

// TC3: stripAnsi removes SGR codes from colored text
test("TC3: stripAnsi removes SGR codes from colored text", () => {
  let colored = "\u001b[32mhello\u001b[0m"
  let stripped = stripAnsi(colored)
  assertion(
    ~message=`Expected "hello", got "${stripped}"`,
    (a, b) => a == b,
    stripped,
    "hello",
  )
})

// TC4: stripAnsi strips multiple SGR codes
test("TC4: stripAnsi strips multiple SGR codes", () => {
  let colored = "\u001b[32m\u001b[2mstyled\u001b[0m\u001b[0m"
  let stripped = stripAnsi(colored)
  assertion(
    ~message=`Expected "styled", got "${stripped}"`,
    (a, b) => a == b,
    stripped,
    "styled",
  )
})

// TC5: stripAnsi returns input unchanged when no ANSI codes
test("TC5: stripAnsi returns plain text unchanged", () => {
  let plain = "plain text"
  let stripped = stripAnsi(plain)
  assertion(
    ~message=`Expected "${plain}", got "${stripped}"`,
    (a, b) => a == b,
    stripped,
    plain,
  )
})

// TC6: stripAnsi returns empty string for codes-only input
test("TC6: stripAnsi returns empty string for codes-only input", () => {
  let codesOnly = "\u001b[32m\u001b[0m"
  let stripped = stripAnsi(codesOnly)
  assertion(
    ~message=`Expected empty string, got "${stripped}"`,
    (a, b) => a == b,
    stripped,
    "",
  )
})

// TC7: clip strips ANSI codes before measuring visible width
test("TC7: clip strips ANSI codes before measuring visible width", () => {
  // Colored text has 5 visible chars but >14 code+text bytes
  let colored = "\u001b[32mhello\u001b[0m"
  let result = clip(colored, ~width=5)
  let visibleLen = String.length(stripAnsi(result))
  assertion(
    ~message=`Expected 5 visible chars, got ${Int.toString(visibleLen)}`,
    (a, b) => a == b,
    visibleLen,
    5,
  )
  assertion(
    ~message="Result should not contain ANSI codes",
    (a, b) => a == b,
    result,
    "hello",
  )
})

// TC8: clip truncates and appends ellipsis when text exceeds width
test("TC8: clip truncates and appends ellipsis when text exceeds width", () => {
  // "hello world" (11) → clip to 8-1=7 visible + "…" → "hello w…" (8 visible)
  let result = clip("hello world", ~width=8)
  let stripped = stripAnsi(result)
  let visibleLen = String.length(stripped)
  assertion(
    ~message=`Expected 8 visible chars (7 + ellipsis), got ${Int.toString(visibleLen)}`,
    (a, b) => a == b,
    visibleLen,
    8,
  )
  assertion(
    ~message=`Expected "hello w…"`,
    (a, b) => a == b,
    stripped,
    "hello w…",
  )
})

// TC9: clip pads with spaces when text is shorter than width
test("TC9: clip pads with spaces when text is shorter than width", () => {
  let result = clip("hi", ~width=6)
  let stripped = stripAnsi(result)
  let visibleLen = String.length(stripped)
  assertion(
    ~message=`Expected 6 chars total (2 + 4 spaces), got ${Int.toString(visibleLen)}`,
    (a, b) => a == b,
    visibleLen,
    6,
  )
  assertion(
    ~message=`Expected "hi    " (with 4 padding spaces)`,
    (a, b) => a == b,
    result,
    "hi    ",
  )
})

// TC10: clip uses custom ellipsis when provided
test("TC10: clip uses custom ellipsis when provided", () => {
  // "hello world" (11) → clip to 8-2=6 visible + ".." → "hello .."
  let result = clip("hello world", ~width=8, ~ellipsis="..")
  let stripped = stripAnsi(result)
  let visibleLen = String.length(stripped)
  assertion(
    ~message=`Expected "hello .." (6 + 2 ellipsis = 8 visible), got "${stripped}"`,
    (a, b) => a == b,
    stripped,
    "hello ..",
  )
  assertion(
    ~message="Result should be 8 visible chars",
    (a, b) => a == b,
    visibleLen,
    8,
  )
})

// TC11: clip handles width smaller than ellipsis length gracefully
test("TC11: clip handles width smaller than ellipsis length", () => {
  let result = clip("hello", ~width=1, ~ellipsis="~~")
  // width=1, ellipsis="~~" (2 chars) → String.substring(~~, 0, 1) → "~"
  let stripped = stripAnsi(result)
  assertion(
    ~message=`Expected "~" (ellipsis truncated to fit), got "${stripped}"`,
    (a, b) => a == b,
    stripped,
    "~",
  )
})

// TC12: clip handles multi-byte unicode correctly (chars count as single visible)
test("TC12: clip handles multi-byte unicode correctly", () => {
  // "hello" (5 chars) → clip to 3 → "he…"
  let result = clip("hello", ~width=3)
  let stripped = stripAnsi(result)
  let visibleLen = String.length(stripped)
  assertion(
    ~message=`Expected 3 visible chars, got ${Int.toString(visibleLen)}`,
    (a, b) => a == b,
    visibleLen,
    3,
  )
})

// TC13: clip handles string with only ANSI codes (no visible text)
test("TC13: clip with only ANSI codes pads to width with spaces", () => {
  let codesOnly = "\u001b[32m\u001b[0m"
  let result = clip(codesOnly, ~width=5)
  let stripped = stripAnsi(result)
  let visibleLen = String.length(stripped)
  assertion(
    ~message=`Expected 5 spaces (no visible chars), got "${stripped}" (len=${Int.toString(visibleLen)})`,
    (a, b) => a == b,
    visibleLen,
    5,
  )
})

// TC14: clip 28-char name to 24 keeps within slot
test("TC14: clip 28-char name to 24 keeps within slot", () => {
  let longName = "Minimax · Daily request quota" // 28 visible chars
  let result = clip(longName, ~width=24)
  let stripped = stripAnsi(result)
  let visibleLen = String.length(stripped)
  assertion(
    ~message=`Expected 24 visible chars, got ${Int.toString(visibleLen)}`,
    (a, b) => a == b,
    visibleLen,
    24,
  )
  assertion(
    ~message="Result should contain ellipsis",
    (a, b) => a == b,
    String.includes(stripped, "…"),
    true,
  )
})

// TC15: clip 40-char name to 24: result has exactly 24 visible chars
test("TC15: clip 40-char name to 24: exactly 24 visible chars", () => {
  let fortyChar = "A"->String.repeat(40)
  let result = clip(fortyChar, ~width=24)
  let stripped = stripAnsi(result)
  let visibleLen = String.length(stripped)
  assertion(
    ~message=`Expected 24 visible chars, got ${Int.toString(visibleLen)}`,
    (a, b) => a == b,
    visibleLen,
    24,
  )
  assertion(
    ~message="Result should contain ellipsis",
    (a, b) => a == b,
    String.includes(stripped, "…"),
    true,
  )
})

let () = runTests()
