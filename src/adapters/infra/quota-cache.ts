// QuotaCache — polling cache adapter implementing the CacheSource port.
// Coalesces concurrent callers onto a single in-flight request (single-flight
// pattern) and bounds history size to guard against memory leaks.

import type { QuotaData } from "../../domain/types.js";
import type { CacheSource } from "../../ports/cache.js";

type Snapshot = {
  readonly at: number; // Unix ms timestamp — used to determine staleness
  readonly data: readonly QuotaData[]; // frozen to prevent external mutation
};

const DEFAULT_INTERVAL_MS = 60_000;
const DEFAULT_MAX_HISTORY = 50;

/**
 * Polling cache for quota data.
 *
 * COALESCING (single-flight): When N callers invoke get() while a fetch is
 * already in-flight, all N attach to the SAME promise — exactly one network
 * round-trip results regardless of N.
 *
 * BOUNDED HISTORY: The history array is capped at maxHistory.  When a new
 * snapshot would exceed the cap, the oldest entry is shifted off (FIFO).  This
 * prevents unbounded memory growth during sustained polling.
 *
 * IMMEDIATE RETURN: When a snapshot exists (even if stale), get() returns it
 * synchronously without blocking on a pending refresh.  This is critical for
 * footer-hook latency — the UI always gets a snapshot immediately.
 *
 * INVALIDATE vs HISTORY: invalidate() clears lastSnapshot and inFlight but
 * preserves history.  This distinction matters for ETTL: even if the live
 * cache is flushed, the historical context used for regression must survive.
 */
export class QuotaCache implements CacheSource {
  // Last successful snapshot; null when the cache has never been populated.
  private lastSnapshot: Snapshot | null = null;

  // Single in-flight fetch promise; null when no request is pending.
  // This is the single-flight anchor — all concurrent callers share it.
  private inFlight: Promise<readonly QuotaData[]> | null = null;

  // FIFO history of all stored snapshots, bounded to maxHistory.
  // Oldest entry is at index 0; shifted off when length would exceed cap.
  private readonly history: Snapshot[] = [];

  private readonly interval: number;
  private readonly maxHistory: number;

  /**
   * @param fetcher  Produces a fresh quota snapshot.
   * @param options.interval    How often to refresh (ms); default 60 000.
   * @param options.maxHistory   Max snapshots to retain; default 50.
   */
  constructor(
    private readonly fetcher: () => Promise<readonly QuotaData[]>,
    options: { interval?: number; maxHistory?: number } = {},
  ) {
    this.interval = options.interval ?? DEFAULT_INTERVAL_MS;
    this.maxHistory = options.maxHistory ?? DEFAULT_MAX_HISTORY;
  }

  async get(): Promise<readonly QuotaData[]> {
    // Single-flight: if a fetch is already in-flight, all callers await it.
    // This prevents a thundering-herd when many footer-hook calls fire at once.
    if (this.inFlight) return this.inFlight;

    // IMMEDIATE RETURN: return the cached snapshot synchronously if one exists.
    // This is the fast path — no async work, no blocking.  The snapshot may be
    // stale (older than interval), but returning stale data immediately is
    // preferable to blocking the UI on a network round-trip.
    if (this.lastSnapshot !== null) return this.lastSnapshot.data;

    // Cold cache — kick off a fetch.  The returned promise is stored as
    // inFlight so concurrent callers coalesce onto it.
    this.inFlight = this.doFetch();
    return this.inFlight;
  }

  invalidate(): void {
    this.lastSnapshot = null;
    this.inFlight = null;
    // History is intentionally NOT cleared — it survives invalidation to
    // preserve ETTL regression context (see class-level comment).
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /** Wraps the raw fetcher and manages snapshot + history lifecycle. */
  private async doFetch(): Promise<readonly QuotaData[]> {
    const data = await this.fetcher();

    // Freeze the result and all entries so callers cannot mutate the cached
    // snapshot.  This enforces immutability at the boundary of the cache.
    const frozen = Object.freeze([...data]) as readonly QuotaData[];

    const snapshot: Snapshot = { at: Date.now(), data: frozen };
    this.lastSnapshot = snapshot;
    this.history.push(snapshot);

    // BOUNDED HISTORY: prune oldest when cap is exceeded.  Using shift()
    // (O(n)) on a small array is acceptable given maxHistory=50 and the
    // relatively slow rate of snapshot creation.
    while (this.history.length > this.maxHistory) {
      this.history.shift();
    }

    this.inFlight = null;
    return frozen;
  }
}
