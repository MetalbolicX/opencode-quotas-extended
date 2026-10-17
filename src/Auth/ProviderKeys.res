// src/Auth/ProviderKeys.res
// Canonical map: provider ID → auth.json key.
// Falls back to returning the id itself when no mapping exists.
// Ported from src/adapters/auth/provider-keys.ts.

let authKey = (providerId: string): string => {
  switch providerId {
  | "openai" => "openai"
  | "zen" => "opencode"
  | "go" => "opencode-go"
  | "zai" => "zai-coding-plan"
  | "kimi" => "kimi-for-coding"
  | "minimax" => "minimax-coding-plan"
  | "anthropic" => "anthropic"
  | "gemini" => "google-gemini"
  | other => other
  }
}

// pi's auth.json keys (pi provider ids), keyed by the ids providers resolve with.
// None = pi is never a source for that provider: Anthropic subscription usage comes
// from Claude Code's login only, and Gemini credential resolution is unchanged.
let piAuthKey = (providerId: string): option<string> => {
  switch providerId {
  | "openai" => Some("openai-codex")
  | "zen" => Some("opencode")
  | "go" | "opencode-go" => Some("opencode-go")
  | "zai" | "zai-coding-plan" => Some("zai")
  | "kimi" => Some("kimi-coding")
  | "minimax" | "minimax-coding-plan" => Some("minimax")
  | _ => None
  }
}
