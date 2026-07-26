// env-source: resolves credentials from environment variables.
import type { Credential } from "../../ports/credentials.js";

const PROVIDER_ENV: Record<string, string | null> = {
  openai: "OPENAI_API_KEY",
  "opencode-zen": null,
  "opencode-go": null,
  anthropic: "ANTHROPIC_API_KEY",
  "google-gemini": "GEMINI_API_KEY",
  "zai-coding-plan": null,
  "kimi-for-coding": null,
  "minimax-coding-plan": null,
};

export function createEnvSource(
  env: Record<string, string | undefined> = process.env as Record<string, string | undefined>,
): (providerId: string) => Credential | null {
  return function get(providerId: string): Credential | null {
    const varName = PROVIDER_ENV[providerId];
    if (!varName) return null;
    const val = env[varName];
    if (!val) return null;
    return { variant: "api", key: val };
  };
}
