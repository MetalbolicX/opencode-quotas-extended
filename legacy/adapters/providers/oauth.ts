// Shared OAuth helper — single-flight 401 refresh + retry, no refresh storms.
// Used by all five coding-plan provider adapters (OpenAI, Zen, Go, z.ai, Kimi, Minimax).
import type { Credential, CredentialSource } from "../../ports/credentials.js";
import type { HttpClient, HttpRequest } from "../../ports/http.js";

/**
 * Injects Authorization header into every request through the returned client.
 * oauth credential → Bearer {access}
 * api credential   → Bearer {key}
 */
const withAuth = (client: HttpClient, cred: Credential): HttpClient => {
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
 * Two-phase in-flight tracker keyed by providerId.
 *
 * Phase 1 — "initial": tracks the first request's credential fetch + fn() call.
 * All concurrent callers for the same providerId share ONE initial promise.
 * The initial promise includes the HTTP call itself, so concurrent callers that
 * arrive before fn() completes all receive the same fn() result (success or 401).
 *
 * Phase 2 — "retry": tracks the refresh + retry cycle after a 401.
 * Concurrent 401s for the same providerId share ONE retry promise.
 * After the retry completes, both the initial and retry entries are deleted so
 * that subsequent sequential 401s start fresh, independent retry cycles.
 *
 * Key separation:
 *   providerId       → initial (credential fetch + fn())
 *   providerId:retry → retry (refreshed credential fetch + retry fn())
 *
 * This ensures that concurrent calls (sharing the same initial promise) don't
 * collide with the retry key, and sequential calls (with settled promises) don't
 * reuse stale retry results.
 */
const _inflight = new Map<string, Promise<unknown>>();

/**
 * Convenience wrapper for providers.
 * Executes `fn` with an auth-injecting HttpClient.
 * - null credential → skips request, returns []
 * - 401            → exactly ONE coalesced refresh (concurrent callers share ONE
 *                    source.get()) + ONE coalesced retry + ONE retry result
 * - Second 401     → returns []
 *
 * Single-flight contract:
 *  - N concurrent callers that all hit 401 → exactly 1 source.get() + 1 fn()
 *  - Different providerIds never coalesce (credential A and B refresh independently)
 *  - After the refresh cycle completes, in-flight entries are deleted so the next
 *    401 starts a completely fresh (non-stale) cycle
 */
export const withOAuth = async <T>(
  source: CredentialSource,
  http: HttpClient,
  providerId: string,
  fn: (client: HttpClient) => Promise<T>,
  timeoutMs = 15_000,
): Promise<T | []> => {
  // ── Phase 1: single-flight initial request ───────────────────────────────
  // Check before starting; concurrent callers for the same providerId all
  // receive the same promise and therefore share ONE fn() execution.
  const cached = _inflight.get(providerId);
  if (cached) {
    const result = await (cached as Promise<T | []>);
    return result;
  }

  // First caller: create the initial promise (credential fetch + fn()).
  // Store it BEFORE fn() starts so any concurrent caller sees it immediately.
  const initialPromise = (async (): Promise<T | []> => {
    const cred = await source.get(providerId);
    if (!cred) return [];
    const client = withAuth(http, cred);
    try {
      return await fn(client);
    } catch (err) {
      const status = (err as { status?: number }).status;
      if (status !== 401) throw err;

      // ── Phase 2: single-flight retry ────────────────────────────────────
      // At least one 401 detected. Concurrent callers all share the same retry.
      const retryKey = `${providerId}:retry`;
      const cachedRetry = _inflight.get(retryKey) as Promise<Credential | null> | undefined;
      if (cachedRetry) {
        // Another caller already started the retry; share it.
        const retryCred = await cachedRetry;
        if (!retryCred) return [];
        return await fn(withAuth(http, retryCred));
      }

      // First 401 for this cycle: create and store the shared retry promise.
      const retryPromise = (async (): Promise<Credential | null> => {
        return await source.get(providerId);
      })();
      _inflight.set(retryKey, retryPromise);
      try {
        const retryCred = await retryPromise;
        if (!retryCred) return [];
        try {
          return await fn(withAuth(http, retryCred));
        } catch (retryErr) {
          const retryStatus = (retryErr as { status?: number }).status;
          if (retryStatus === 401) return [];
          throw retryErr;
        }
      } finally {
        _inflight.delete(retryKey);
      }
    }
  })();

  _inflight.set(providerId, initialPromise as Promise<unknown>);
  try {
    return await initialPromise;
  } finally {
    _inflight.delete(providerId);
  }
}
