// src/Infra/PathsTests.res
open RescriptTest

autoBoot := false

let envOf = (key: string, value: string): dict<string> => {
  let d = Dict.make()
  Dict.set(d, key, value)
  d
}

test("getAuthJsonPath honors XDG_DATA_HOME", () => {
  let env = envOf("XDG_DATA_HOME", "/custom")
  let result = Infra.getAuthJsonPath(~env=Some(env))
  assertion(
    ~message=`Expected "/custom/opencode/auth.json", got "${result}"`,
    (a, b) => a == b,
    result,
    "/custom/opencode/auth.json",
  )
})

test("getAuthJsonPath falls back to homedir when XDG unset", () => {
  let env = Dict.make()
  let result = Infra.getAuthJsonPath(~env=Some(env))
  assertion(
    ~message=`Expected path to end with /opencode/auth.json, got "${result}"`,
    (a, b) => a == b,
    String.endsWith(result, "/opencode/auth.json"),
    true,
  )
})

test("getAuthJsonPath returns string ending in auth.json when XDG_DATA_HOME not set", () => {
  let result = Infra.getAuthJsonPath(~env=None)
  assertion(
    ~message=`Expected path to end with auth.json, got "${result}"`,
    (a, b) => a == b,
    String.endsWith(result, "auth.json"),
    true,
  )
})

let () = runTests()
