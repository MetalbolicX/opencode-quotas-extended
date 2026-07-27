// Canonical map: provider ID → auth.json key.
export const AUTH_KEY: Record<string, string> = {
  openai: "openai",
  zen: "opencode",
  go: "opencode-go",
  zai: "zai-coding-plan",
  kimi: "kimi-for-coding",
  minimax: "minimax-coding-plan",
  anthropic: "anthropic",
  gemini: "google-gemini",
};

export function authKey(id: string): string {
  return AUTH_KEY[id] ?? id;
}
