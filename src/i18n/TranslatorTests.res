// Translator / i18n module tests.
open RescriptTest
open Translator

autoBoot := false

// ─── createI18nTranslator ────────────────────────────────────────────────────

test("createI18nTranslator with empty dict returns translator that returns key for unknown keys", () => {
  let translator = Translator.createI18nTranslator(Dict.make())
  let result = translator.t("unknown.key", None)
  assertion(
    ~message=`Expected "unknown.key", got "${result}"`,
    (a, b) => a == b,
    result,
    "unknown.key",
  )
})

// ─── interpolate — single placeholder ────────────────────────────────────────

test("interpolate substitutes a single {var} placeholder", () => {
  let catalog = Dict.fromArray([("greet", "Hello, {name}!")])
  let translator = Translator.createI18nTranslator(catalog)
  let vars = Dict.fromArray([("name", "World")])
  let result = translator.t("greet", Some(vars))
  assertion(
    ~message=`Expected "Hello, World!", got "${result}"`,
    (a, b) => a == b,
    result,
    "Hello, World!",
  )
})

// ─── interpolate — multiple placeholders ─────────────────────────────────────

test("interpolate substitutes multiple {var} placeholders in one string", () => {
  let catalog = Dict.fromArray([("greet", "Hello, {name}. You have {count} messages.")])
  let translator = Translator.createI18nTranslator(catalog)
  let vars = Dict.fromArray([("name", "Alice"), ("count", "5")])
  let result = translator.t("greet", Some(vars))
  assertion(
    ~message=`Expected "Hello, Alice. You have 5 messages.", got "${result}"`,
    (a, b) => a == b,
    result,
    "Hello, Alice. You have 5 messages.",
  )
})

// ─── Missing key returns key itself ──────────────────────────────────────────

test("missing key returns the key itself, not an error", () => {
  let catalog = Dict.fromArray([("existing", "Value")])
  let translator = Translator.createI18nTranslator(catalog)
  let result = translator.t("nonexistent.key", None)
  assertion(
    ~message=`Expected "nonexistent.key", got "${result}"`,
    (a, b) => a == b,
    result,
    "nonexistent.key",
  )
})

runTests()
