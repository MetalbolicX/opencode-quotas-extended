// json-file-history: HistoryStore adapter with debounced write and reset detection.
import type { HistoryStore } from "../../ports/history.js";
import type { HistoryPoint } from "../../domain/types.js";
import { detectReset } from "../../domain/reset.js";

interface HFile { history: Record<string, HistoryPoint[]>; }
interface Deps { readFileSync: (p: string) => string; writeFileSync: (p: string, d: string) => void; existsSync: (p: string) => boolean; now?: () => number; }

function load(path: string, d: Deps): HFile {
  if (!d.existsSync(path)) return { history: {} };
  try { return JSON.parse(d.readFileSync(path)) as HFile; } catch { return { history: {} }; }
}
function save(path: string, data: HFile, d: Deps): void { d.writeFileSync(path, JSON.stringify(data, null, 2)); }

export function createHistoryStore(filePath: string, deps: Deps): HistoryStore {
  let pending: ReturnType<typeof setTimeout> | null = null;
  const DEBOUNCE_MS = 5000;
  function sched(path: string, data: HFile): void {
    if (pending) clearTimeout(pending);
    pending = setTimeout(() => { save(path, data, deps); pending = null; }, DEBOUNCE_MS);
  }
  return {
    async append(providerId: string, point: HistoryPoint): Promise<void> {
      const data = load(filePath, deps);
      const existing = data.history[providerId] ?? [];
      const prev = existing.at(-1);
      data.history[providerId] = (prev && detectReset(prev, { id: providerId, providerName: providerId, used: point.used, limit: point.limit, unit: "", reset: null, predictedReset: null, window: "daily" })) ? [point] : [...existing, point];
      sched(filePath, data);
    },
    async getHistory(providerId: string, windowMs: number): Promise<HistoryPoint[]> {
      const cutoff = (deps.now ? deps.now() : Date.now()) - windowMs;
      return (load(filePath, deps).history[providerId] ?? []).filter((p) => p.timestamp >= cutoff);
    },
    async prune(maxAgeMs: number): Promise<void> {
      const cutoff = (deps.now ? deps.now() : Date.now()) - maxAgeMs;
      const data = load(filePath, deps);
      for (const pid of Object.keys(data.history)) data.history[pid] = data.history[pid].filter((p) => p.timestamp >= cutoff);
      save(filePath, data, deps);
    },
    resetDetected(providerId: string, prev: HistoryPoint, used: number, limit: number | null): boolean {
      return detectReset(prev, { id: providerId, providerName: providerId, used, limit, unit: "", reset: null, predictedReset: null, window: "daily" });
    },
  };
}
