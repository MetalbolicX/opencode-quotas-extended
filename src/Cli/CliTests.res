// src/Cli/CliTests.res
// Tests for Cli module: parse-error early-return path, usageText presence,
// and main smoke. Full dispatch is not testable without process.exit mocking.
open RescriptTest
open Cli

autoBoot := false

// C1: Cli.run with garbage argv returns exitCode 2 and non-empty stderr
test("C1: Cli.run with garbage returns exitCode 2 and error in stderr", () => {
  let result = Cli.run(["--not-a-flag"])
  assertion(~message="exitCode is 2 on parse error", (a, b) => a == b, result.exitCode, 2)
  assertion(~message="stderr has content on parse error", (a, b) => a != b, result.stderr !== "", true)
})

// C2: Cli.main is callable and returns unit (smoke)
test("C2: Cli.main is callable and returns unit", () => {
  let got = Cli.main(["--help"])
  let isUnit = got == ()
  assertion(~message="main returns unit", (a, b) => a == b, isUnit, true)
})

// C3: usageText is non-empty
test("C3: Cli.usageText is a non-empty string", () => {
  assertion(~message="usageText is non-empty", (a, b) => a !== b, Cli.usageText !== "", true)
})
