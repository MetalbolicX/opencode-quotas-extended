// CacheSource — domain reads cached quota data through this port (DIP).
// The cache sits in front of the provider fetch pipeline so high-frequency
// footer hook calls do not fan out into N×8 live requests.

import type { QuotaData } from "../domain/types.js";

/**
 * Polling cache port.  The domain/pipeline depends on this abstraction so the
 * concrete QuotaCache adapter can be swapped (e.g., for a Redis-backed cache)
 * without touching any domain or pipeline code.
 */
export interface CacheSource {
  /**
   * Returns the cached quota snapshot, fetching fresh data if the cache is empty
   * or has been invalidated.  Concurrent callers are coalesced onto a single
   * in-flight request (single-flight pattern) so a storm of N calls produces
   * exactly one network round-trip.
   *
   * When a snapshot is already cached it is returned IMMEDIATELY without
   * blocking — the caller always gets a snapshot synchronously.
   */
  get(): Promise<readonly QuotaData[]>;

  /**
   * Clears the cached snapshot and any in-flight request.  Does NOT clear
   * history — retained snapshots survive invalidation so ETTL prediction
   * retains its historical context.
   */
  invalidate(): void;
}
