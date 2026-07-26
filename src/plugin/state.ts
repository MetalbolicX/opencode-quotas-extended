// Plugin state — per-message mutex + processed/pending dedup with injectable clock.
export type Clock = () => number;

const MAX_TRACKED = 1000;

/** Simple per-key mutex. acquire() returns a release function. */
export class SimpleLock {
  private locks = new Map<string, Promise<void>>();

  async acquire(key: string): Promise<() => void> {
    const prev = this.locks.get(key) ?? Promise.resolve();
    let settle: () => void;
    const next = new Promise<void>((res) => { settle = res; });
    this.locks.set(key, next);
    await prev;
    return () => {
      settle!();
      if (this.locks.get(key) === next) this.locks.delete(key);
    };
  }
}

/** Per-message processed/pending dedup state. */
export class PluginState {
  private processedSet = new Set<string>();
  private processedOrder: string[] = [];
  private pendingSet = new Set<string>();
  private readonly lock: SimpleLock;

  constructor(private readonly clock: Clock) {
    this.lock = new SimpleLock();
  }

  isProcessed(messageID: string): boolean {
    return this.processedSet.has(messageID);
  }

  isPending(messageID: string): boolean {
    return this.pendingSet.has(messageID);
  }

  markProcessed(messageID: string): void {
    if (this.processedSet.has(messageID)) return;
    this.processedSet.add(messageID);
    this.processedOrder.push(messageID);
    this.pendingSet.delete(messageID);
    while (this.processedOrder.length > MAX_TRACKED) {
      const oldest = this.processedOrder.shift();
      if (oldest) this.processedSet.delete(oldest);
    }
  }

  markPending(messageID: string): void {
    this.pendingSet.add(messageID);
  }

  /** Acquire a per-message lock. Caller MUST call the returned release. */
  async acquireLock(messageID: string): Promise<() => void> {
    const release = await this.lock.acquire(messageID);
    return async () => {
      await release();
    };
  }


}
