// src/rendering/ColorsTests.res
// Tests for Colors module — ANSI color name system.
// Covers: colorMap (16 colors, ANSI SGR codes), ansiColor wrapping, dim.
open RescriptTest
open Colors

autoBoot := false

// The 16 expected color names (standard + bright variants)
let all16Colors = [
  "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
  "brightBlack", "brightRed", "brightGreen", "brightYellow",
  "brightBlue", "brightMagenta", "brightCyan", "brightWhite",
]

// C1: colorMap contains all 16 expected color names
test("C1: colorMap contains all 16 expected color names", () => {
  let missing = all16Colors->Array.filter(name => {
    switch Dict.get(colorMap, name) {
    | Some(_) => false
    | None => true
    }
  })
  assertion(
    ~message=`All 16 colors should be present. Missing: ${missing->Array.join(", ")}`,
    (a, b) => a == b,
    missing->Array.length,
    0,
  )
})

// C2: all color values are valid ANSI SGR codes (30-37 or 90-97)
test("C2: all 16 color values are valid ANSI SGR codes (30-37, 90-97)", () => {
  let allValid = all16Colors->Array.every(name => {
    switch Dict.get(colorMap, name) {
    | Some(code) =>
      let n = try {
        Int.fromString(code)
      } catch {
      | _ => None
      }
      switch n {
      | Some(v) => (v >= 30 && v <= 37) || (v >= 90 && v <= 97)
      | None => false
      }
    | None => false
    }
  })
  assertion(
    ~message="all color values should be valid SGR codes",
    (a, b) => a == b,
    allValid,
    true,
  )
})

// C3: ansiColor("green", "hello") produces correct ANSI-wrapped output
test("C3: ansiColor(green, hello) wraps text in correct ANSI codes", () => {
  let out = ansiColor("green", "hello")
  // "\u001b[32mhello\u001b[0m" — green=32, reset=0
  let expected = "\u001b[32mhello\u001b[0m"
  assertion(
    ~message=`Expected ${expected}, got ${out}`,
    (a, b) => a == b,
    out,
    expected,
  )
})

// C4: ansiColor("brightRed", "warn") produces correct ANSI-wrapped output
test("C4: ansiColor(brightRed, warn) wraps text in \\x1b[91m...\\x1b[0m", () => {
  let out = ansiColor("brightRed", "warn")
  let expected = "\u001b[91mwarn\u001b[0m"
  assertion(
    ~message=`Expected ${expected}, got ${out}`,
    (a, b) => a == b,
    out,
    expected,
  )
})

// C5: ansiColor("blue", "") produces empty ANSI-wrapped string
test("C5: ansiColor(blue, empty string) produces ANSI-wrapped empty string", () => {
  let out = ansiColor("blue", "")
  let expected = "\u001b[34m\u001b[0m"
  assertion(
    ~message=`Expected ${expected}, got ${out}`,
    (a, b) => a == b,
    out,
    expected,
  )
})

// C6: ansiColor throws for invalid color name
test("C6: ansiColor throws for invalid color name", () => {
  throws(
    ~message="ansiColor(gray, test) should throw",
    () => {
      let _ = ansiColor("gray", "test")
    },
  )
})

// C7: ansiColor throws for empty string color name
test("C7: ansiColor throws for empty string color name", () => {
  throws(
    ~message="ansiColor(empty, test) should throw",
    () => {
      let _ = ansiColor("", "test")
    },
  )
})

// C8: dim wraps text in SGR 2 + reset
test("C8: dim(hello) wraps text in SGR 2 + reset", () => {
  let out = dim("hello")
  let expected = "\u001b[2mhello\u001b[0m"
  assertion(
    ~message=`Expected ${expected}, got ${out}`,
    (a, b) => a == b,
    out,
    expected,
  )
})

// C9: dim returns SGR-wrapped empty string for empty input
test("C9: dim(empty) returns SGR-wrapped empty string", () => {
  let out = dim("")
  let expected = "\u001b[2m\u001b[0m"
  assertion(
    ~message=`Expected ${expected}, got ${out}`,
    (a, b) => a == b,
    out,
    expected,
  )
})

// C10: validColorNames array is non-empty and contains the 16 standard colors
test("C10: validColorNames contains all 16 standard colors", () => {
  let allPresent = all16Colors->Array.every(c => {
    validColorNames->Array.some(v => v == c)
  })
  assertion(
    ~message="validColorNames should contain all 16 standard colors",
    (a, b) => a == b,
    allPresent,
    true,
  )
})

let () = runTests()
