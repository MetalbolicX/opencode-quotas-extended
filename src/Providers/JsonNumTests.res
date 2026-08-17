// src/Providers/JsonNumTests.res
// Tests for JsonNum.toNum — the shared %-stripping number parser.
// Also serves as characterization tests documenting the PREVIOUS divergent
// behavior of Anthropic.res and Minimax.res (which returned None for "85%"
// before being unified to the canonical %-stripping behavior).
open RescriptTest

autoBoot := false

// === Canonical %-stripping behavior ===

// JN1: JSON.Number passes through as-is
test("JN1: JSON.Number returns Some(float)", () => {
  let result = JsonNum.toNum(JSON.Number(42.5))
  assertion(
    ~message=`Expected Some(42.5), got ${Belt.Option.map(result, Belt.Float.toString)->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    Some(42.5),
  )
})

// JN2: plain numeric string parses successfully
test("JN2: numeric string parses to Some(float)", () => {
  let result = JsonNum.toNum(JSON.String("123.5"))
  assertion(
    ~message=`Expected Some(123.5), got ${Belt.Option.map(result, Belt.Float.toString)->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    Some(123.5),
  )
})

// JN3: string with trailing % is stripped and parsed — canonical behavior
test("JN3: '85%' parses to Some(85.0) after %-stripping", () => {
  let result = JsonNum.toNum(JSON.String("85%"))
  assertion(
    ~message=`Expected Some(85.0), got ${Belt.Option.map(result, Belt.Float.toString)->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    Some(85.0),
  )
})

// JN4: whitespace-padded numeric string is trimmed then parsed
test("JN4: '  42  ' parses to Some(42.0) after trim", () => {
  let result = JsonNum.toNum(JSON.String("  42  "))
  assertion(
    ~message=`Expected Some(42.0), got ${Belt.Option.map(result, Belt.Float.toString)->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    Some(42.0),
  )
})

// JN5: empty string returns None
test("JN5: empty string returns None", () => {
  let result = JsonNum.toNum(JSON.String(""))
  assertion(
    ~message=`Expected None for empty string, got ${Belt.Option.map(result, Belt.Float.toString)->Belt.Option.getWithDefault("Some")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

// JN6: non-numeric garbage string returns None
test("JN6: garbage string returns None", () => {
  let result = JsonNum.toNum(JSON.String("not-a-number"))
  assertion(
    ~message=`Expected None for garbage, got ${Belt.Option.map(result, Belt.Float.toString)->Belt.Option.getWithDefault("Some")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

// JN7: null-ish JSON values return None
test("JN7: JSON.Null returns None", () => {
  let result = JsonNum.toNum(JSON.Null)
  assertion(
    ~message=`Expected None for JSON.Null, got ${Belt.Option.map(result, Belt.Float.toString)->Belt.Option.getWithDefault("Some")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

// JN8: JSON.Array returns None (not a scalar)
test("JN8: JSON.Array returns None", () => {
  let result = JsonNum.toNum(JSON.Array([]))
  assertion(
    ~message=`Expected None for JSON.Array, got ${Belt.Option.map(result, Belt.Float.toString)->Belt.Option.getWithDefault("Some")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

// JN9: JSON.Object returns None (not a scalar)
test("JN9: JSON.Object returns None", () => {
  let result = JsonNum.toNum(JSON.Object(Dict.fromArray([])))
  assertion(
    ~message=`Expected None for JSON.Object, got ${Belt.Option.map(result, Belt.Float.toString)->Belt.Option.getWithDefault("Some")}`,
    (a, b) => a == b,
    result,
    None,
  )
})

// JN10: negative number in JSON.String parses correctly
test("JN10: '-17.5' parses to Some(-17.5)", () => {
  let result = JsonNum.toNum(JSON.String("-17.5"))
  assertion(
    ~message=`Expected Some(-17.5), got ${Belt.Option.map(result, Belt.Float.toString)->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    Some(-17.5),
  )
})

// JN11: '100%' parses to Some(100.0) after %-stripping
test("JN11: '100%' parses to Some(100.0)", () => {
  let result = JsonNum.toNum(JSON.String("100%"))
  assertion(
    ~message=`Expected Some(100.0), got ${Belt.Option.map(result, Belt.Float.toString)->Belt.Option.getWithDefault("None")}`,
    (a, b) => a == b,
    result,
    Some(100.0),
  )
})
