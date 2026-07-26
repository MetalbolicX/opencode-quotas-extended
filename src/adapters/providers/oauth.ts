// Shared OAuth helper — single-flight 401 refresh + retry, no refresh storms.
// Used by all five coding-plan provider adapters (OpenAI, Zen, Go, z.ai, Kimi, Minimax).
import type { Credential, CredentialSource } from "../../ports/credentials.js";
import type { HttpClient, HttpRequest } from "../../ports/http.js";

/**
 * Injects Authorization header into every request through the returned client.
 * oauth credential → Bearer {access}
 * api credential   → Bearer {key}
 */
function withAuth(client: HttpClient, cred: Credential): HttpClient {
  const auth = cred.variant === "oauth"
    ? `Bearer ${cred.access}`
    : cred.variant === "api"
    ? `Bearer ${cred.key}`
    : `Bearer ${process.env[(cred as { envVar: string }).envVar] ?? ""}`;
  return {
    async request<T>(req: HttpRequest, opts: { timeoutMs: number; retries: number; redact: true }): Promise<T> {
      return client.request<T>(
        { ...req, headers: { ...req.headers, Authorization: auth } },
        opts,
      );
    },
  };
}

/**
 * Convenience wrapper for providers.
 * Executes `fn` with an auth-injecting HttpClient.
 * - null credential → skips request, returns []
 * - 401            → exactly ONE refresh (re-fetches credential) + ONE retry
 * - Second 401     → returns []
 */
export async function withOAuth<T>(
  source: CredentialSource,
  http: HttpClient,
  providerId: string,
  fn: (client: HttpClient) => Promise<T>,
  timeoutMs = 15_000,
): Promise<T | []> {
  const cred = await source.get(providerId);
  if (!cred) return [];

  const client = withAuth(http, cred);
  try {
    return await fn(client);
  } catch (err) {
    const status = (err as { status?: number }).status;
    if (status !== 401) throw err;

    // Single refresh + one retry with refreshed credentials
    const refreshed = await source.get(providerId);
    if (!refreshed) return [];
    const refreshedClient = withAuth(http, refreshed);
    try {
      return await fn(refreshedClient);
    } catch (retryErr) {
      const retryStatus = (retryErr as { status?: number }).status;
      if (retryStatus === 401) return [];
      throw retryErr;
    }
  }
}
