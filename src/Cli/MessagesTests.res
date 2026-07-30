// src/Cli/MessagesTests.res
// Tests for Messages: M1–M4 scenarios from SDD spec.
// REQ-CRED-1..5: credential diagnostic formatters.
open RescriptTest
open Messages

autoBoot := false

// M1: formatMissingAuthJson contains key lines
test("M1: formatMissingAuthJson contains expected lines", () => {
  let path = "/tmp/nonexistent/auth.json"
  let msg = formatMissingAuthJson(path)
  assertion(~message="contains 'No OpenCode subscription file found.'", (a, b) => a == b, true, String.includes(msg, "No OpenCode subscription file found."))
  assertion(~message="contains checked path", (a, b) => a == b, true, String.includes(msg, `Checked: ${path}`))
  assertion(~message="contains opencode auth login hint", (a, b) => a == b, true, String.includes(msg, "opencode auth login"))
  assertion(~message="contains API key hint", (a, b) => a == b, true, String.includes(msg, "OPENAI_API_KEY"))
})

// M2: formatNoSubscriptions contains key lines
test("M2: formatNoSubscriptions contains expected lines", () => {
  let msg = formatNoSubscriptions()
  assertion(~message="contains 'No subscriptions'", (a, b) => a == b, true, String.includes(msg, "No subscriptions with credentials found."))
  assertion(~message="contains run hint", (a, b) => a == b, true, String.includes(msg, "opencode-quotas -l"))
})

// M3: formatNoCredentialsForProvider with available providers
test("M3: formatNoCredentialsForProvider with available list", () => {
  let msg = formatNoCredentialsForProvider("openai", ["anthropic", "gemini"])
  assertion(~message="contains provider id", (a, b) => a == b, true, String.includes(msg, "openai"))
  assertion(~message="contains available list", (a, b) => a == b, true, String.includes(msg, "anthropic, gemini"))
})

// M4: formatNoCredentialsForProvider with no available
test("M4: formatNoCredentialsForProvider with empty list", () => {
  let msg = formatNoCredentialsForProvider("kimi", [])
  assertion(~message="contains provider id", (a, b) => a == b, true, String.includes(msg, "kimi"))
  assertion(~message="contains '(none)'", (a, b) => a == b, true, String.includes(msg, "(none)"))
})

// M5: formatProviderFetchErrors with multiple errors
test("M5: formatProviderFetchErrors with multiple errors", () => {
  let errors = Dict.fromArray([
    ("openai", "timeout"),
    ("anthropic", "unauthorized"),
  ])
  let msg = formatProviderFetchErrors(errors)
  assertion(~message="contains header", (a, b) => a == b, true, String.includes(msg, "Provider fetch failures:"))
  assertion(~message="contains openai error", (a, b) => a == b, true, String.includes(msg, "openai: timeout"))
  assertion(~message="contains anthropic error", (a, b) => a == b, true, String.includes(msg, "anthropic: unauthorized"))
})

// M6: formatProviderFetchErrors with single error
test("M6: formatProviderFetchErrors with single error", () => {
  let errors = Dict.fromArray([("gemini", "rate limit")])
  let msg = formatProviderFetchErrors(errors)
  assertion(~message="contains header and error", (a, b) => a == b, true, String.includes(msg, "Provider fetch failures:") && String.includes(msg, "gemini: rate limit"))
})

let () = runTests()
