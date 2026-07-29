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
