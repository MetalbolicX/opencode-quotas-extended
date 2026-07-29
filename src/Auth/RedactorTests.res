// src/Auth/RedactorTests.res
// Tests for Redactor module — covers spec scenarios R1 through R6.
open RescriptTest

autoBoot := false

// Helper: make a JSON object from an array of key-value pairs
let mkObj = (pairs: array<(string, JSON.t)>): JSON.t => {
  JSON.Object(Dict.fromArray(pairs))
}

// Helper: stringify an option<JSON.t> for assertion messages
let optToString = (opt: option<JSON.t>): string => {
  switch opt {
  | Some(v) => JSON.stringify(v)
  | None => "None"
  }
}

// R1: mask an sk- prefixed value (4 visible chars + ****)
test("R1: sk- prefix key is masked with 4 visible chars", () => {
  let input = mkObj([("key", JSON.String("sk-abc123"))])
  let result = Redactor.redact(Some(input))
  let expected = mkObj([("key", JSON.String("sk-a****"))])
  assertion(
    ~message="Expected \"sk-a****\", got " ++ optToString(result),
    (a, b) => a == b,
    result,
    Some(expected),
  )
})

// R2: plain (non-sk) value gets 3 visible chars + ****
test("R2: plain access token is masked with 3 visible chars", () => {
  let input = mkObj([("access", JSON.String("abcdefg"))])
  let result = Redactor.redact(Some(input))
  let expected = mkObj([("access", JSON.String("abc****"))])
  assertion(
    ~message="Expected \"abc****\", got " ++ optToString(result),
    (a, b) => a == b,
    result,
    Some(expected),
  )
})

// R3: short value is min-clamped (2 visible chars + ****)
test("R3: short token is min-clamped to its length", () => {
  let input = mkObj([("token", JSON.String("ab"))])
  let result = Redactor.redact(Some(input))
  let expected = mkObj([("token", JSON.String("ab****"))])
  assertion(
    ~message="Expected \"ab****\", got " ++ optToString(result),
    (a, b) => a == b,
    result,
    Some(expected),
  )
})

// R4: nested object with sensitive fields masked and non-sensitive preserved
test("R4: nested object recurses and preserves non-sensitive fields", () => {
  let input = mkObj([
    ("variant", JSON.String("oauth")),
    ("access", JSON.String("abc123")),
    ("refresh", JSON.String("r")),
    ("expires", JSON.Number(5.0)),
  ])
  let result = Redactor.redact(Some(input))
  let expected = mkObj([
    ("variant", JSON.String("oauth")),
    ("access", JSON.String("abc****")),
    ("refresh", JSON.String("r****")),
    ("expires", JSON.Number(5.0)),
  ])
  assertion(
    ~message="Expected access=\"abc****\", refresh=\"r****\", expires=5, got " ++ optToString(result),
    (a, b) => a == b,
    result,
    Some(expected),
  )
})

// R5: array elements are each redacted
test("R5: array elements are each redacted", () => {
  let input = JSON.Array([mkObj([("key", JSON.String("sk-x1yz"))])])
  let result = Redactor.redact(Some(input))
  let expected = JSON.Array([mkObj([("key", JSON.String("sk-x****"))])])
  assertion(
    ~message="Expected key=\"sk-x****\", got " ++ optToString(result),
    (a, b) => a == b,
    result,
    Some(expected),
  )
})

// R6: null passthrough and non-string sensitive values preserved as-is
test("R6a: null input returns null", () => {
  let result = Redactor.redact(None)
  assertion(
    ~message="Expected None for null input",
    (a, b) => a == b,
    result,
    None,
  )
})

test("R6b: non-string sensitive value is preserved as-is (no coercion)", () => {
  let input = mkObj([("key", JSON.Number(123.0))])
  let result = Redactor.redact(Some(input))
  let expected = mkObj([("key", JSON.Number(123.0))])
  assertion(
    ~message="Expected key=123 (not masked), got " ++ optToString(result),
    (a, b) => a == b,
    result,
    Some(expected),
  )
})

let () = runTests()
