// src/Cli/Messages.res
// Diagnostic string formatters for credential and provider errors.
// Ported from src/cli/messages.ts.
// REQ-CRED-1..5.

let formatMissingAuthJson = (path: string): string => {
  [
    "No OpenCode subscription file found.",
    `Checked: ${path}`,
    "",
    "Add API keys via:",
    "  opencode auth login",
    "  Or set OPENAI_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY / MINIMAX_API_KEY",
  ]->Array.joinUnsafe("\n")
}

let formatNoSubscriptions = (): string => {
  [
    "No subscriptions with credentials found.",
    "",
    "Configured providers need API keys. Run 'opencode-quotas -l' after adding keys.",
  ]->Array.joinUnsafe("\n")
}

let formatNoCredentialsForProvider = (providerId: string, available: array<string>): string => {
  let availStr = if available->Array.length > 0 {
    available->Array.join(", ")
  } else {
    "(none)"
  }
  [
    `No credentials found for '${providerId}'.`,
    "",
    `Available: ${availStr}`,
  ]->Array.joinUnsafe("\n")
}

let formatProviderFetchErrors = (errors: dict<string>): string => {
  let lines: array<string> = ["Provider fetch failures:"]
  let keys = errors->Dict.keysToArray
  let _ = keys->Array.map(key => {
    let msg = switch errors->Dict.get(key) {
    | Some(m) => m
    | None => ""
    }
    lines->Array.push(`  ${key}: ${msg}`)
  })
  lines->Array.joinUnsafe("\n")
}
