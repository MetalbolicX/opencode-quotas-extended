// Credential and subscription diagnostic messages.
// REQ-CRED-1..5: friendly messaging when auth.json is missing, no subscriptions
// have credentials, no credentials for a provider, or provider fetch fails.

/**
 * Message shown when the auth.json file does not exist at the expected path.
 * Covers REQ-CRED-1.
 */
export function formatMissingAuthJson(path: string): string {
  return [
    "No OpenCode subscription file found.",
    `Checked: ${path}`,
    "",
    "Add API keys via:",
    "  opencode auth login",
    "  Or set OPENAI_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY",
  ].join("\n");
}

/**
 * Message shown when no registered providers have credentials configured.
 * Covers REQ-CRED-2.
 */
export function formatNoSubscriptions(): string {
  return [
    "No subscriptions with credentials found.",
    "",
    "Configured providers need API keys. Run 'opencode-quotas -l' after adding keys.",
  ].join("\n");
}

/**
 * Message shown when the user requests a specific provider (-p) but that
 * provider has no credentials available.
 * Covers REQ-CRED-3.
 */
export function formatNoCredentialsForProvider(
  providerId: string,
  available: readonly string[],
): string {
  return [
    `No credentials found for '${providerId}'.`,
    "",
    `Available: ${available.join(", ") || "(none)"}`,
  ].join("\n");
}

/**
 * Summary of provider fetch failures for inclusion in partial-result output.
 * Covers REQ-CRED-5.
 */
export function formatProviderFetchErrors(
  errors: Readonly<Record<string, string>>,
): string {
  const lines: string[] = ["Provider fetch failures:"];
  for (const [id, msg] of Object.entries(errors)) {
    lines.push(`  ${id}: ${msg}`);
  }
  return lines.join("\n");
}
