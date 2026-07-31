// WU-5 RED: Credential and subscription message formatters.
// REQ-CRED-1..5: friendly messaging when auth.json is missing, no subscriptions
// have credentials, no credentials for a provider, or provider fetch fails.
import { describe, expect, it } from "vitest";
import {
  formatMissingAuthJson,
  formatNoSubscriptions,
  formatNoCredentialsForProvider,
  formatProviderFetchErrors,
} from "../../../legacy/cli/messages.js";

describe("formatMissingAuthJson", () => {
  it("returns no-subscription-file message with the checked path", () => {
    const result = formatMissingAuthJson("/some/path/auth.json");
    expect(result).toContain("No OpenCode subscription file found.");
    expect(result).toContain("Checked: /some/path/auth.json");
    expect(result).toContain("opencode auth login");
    expect(result).toContain("OPENAI_API_KEY");
    expect(result).toContain("ANTHROPIC_API_KEY");
    expect(result).toContain("GEMINI_API_KEY");
  });
});

describe("formatNoSubscriptions", () => {
  it("returns no-subscriptions-with-credentials message", () => {
    const result = formatNoSubscriptions();
    expect(result).toContain("No subscriptions with credentials found.");
    expect(result).toContain("opencode-quotas -l");
    expect(result).toContain("adding keys");
  });
});

describe("formatNoCredentialsForProvider", () => {
  it("returns missing-credential message for provider", () => {
    const result = formatNoCredentialsForProvider("openai", ["openai", "anthropic", "minimax"]);
    expect(result).toContain("No credentials found for 'openai'.");
    expect(result).toContain("Available: openai, anthropic, minimax");
  });

  it("handles empty available list", () => {
    const result = formatNoCredentialsForProvider("unknown", []);
    expect(result).toContain("No credentials found for 'unknown'.");
    expect(result).toContain("Available: (none)");
  });
});

describe("formatProviderFetchErrors", () => {
  it("returns provider fetch failure summary", () => {
    const errors: Record<string, string> = {
      openai: "rate limit exceeded",
      minimax: "connection refused",
    };
    const result = formatProviderFetchErrors(errors);
    expect(result).toContain("Provider fetch failures:");
    expect(result).toContain("openai: rate limit exceeded");
    expect(result).toContain("minimax: connection refused");
  });

  it("handles empty errors", () => {
    const result = formatProviderFetchErrors({});
    expect(result).toContain("Provider fetch failures:");
  });
});
