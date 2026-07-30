// src/Cli/CliTests.res
// Tests for Cli module: parse-error early-return path, usageText presence,
// and main smoke. Full dispatch is not testable without process.exit mocking.
open RescriptTest
open Cli

autoBoot := false

// C1: Cli.run with garbage argv returns exitCode 2 and non-empty stderr
testAsync("C1: Cli.run with garbage returns exitCode 2 and error in stderr", callback => {
  let _ = Cli.run(["--not-a-flag"])
  ->Promise.then(result => {
    assertion(~message="exitCode is 2 on parse error", (a, b) => a == b, result.exitCode, 2)
    assertion(~message="stderr has content on parse error", (a, b) => a == b, result.stderr !== "", true)
    callback()
    Promise.resolve()
  })
})

// C2: Cli.main is callable (smoke)
// process.exit terminates the process, so this can only verify the call site compiles.
test("C2: Cli.main is callable", () => {
  let _ = Cli.main(["--help"])
  ()
})

// C3: usageText is non-empty
test("C3: Cli.usageText is a non-empty string", () => {
  assertion(~message="usageText is non-empty", (a, b) => a == b, Cli.usageText !== "", true)
})

let () = runTests()
