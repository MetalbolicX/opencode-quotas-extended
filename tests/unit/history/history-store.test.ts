// RED → GREEN: json-file history store — append, prune, reset-detection, debounce.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import historyFIXTURE from "../../fixtures/history/quota-history.json";

const NOW = 1753005000000;
const mockRead = vi.fn(), mockWrite = vi.fn(), mockExists = vi.fn();
vi.mock("node:fs", () => ({ readFileSync: mockRead, writeFileSync: mockWrite, existsSync: mockExists }));

function deps() {
  return {
    readFileSync: (p: string) => { if (!mockExists(p)) { const e = new Error("ENOENT") as Error & { code: string }; e.code = "ENOENT"; throw e; } return mockRead(p); },
    writeFileSync: (p: string, d: string) => mockWrite(p, d), existsSync: (p: string) => mockExists(p),
  };
}

const loadHistory = () => import("../../../legacy/adapters/infra/json-file-history.js");

describe("json-file-history", () => {
  beforeEach(() => { vi.resetAllMocks(); mockExists.mockReturnValue(true); mockRead.mockReturnValue(JSON.stringify(historyFIXTURE)); mockWrite.mockImplementation(() => {}); });
  afterEach(() => vi.useRealTimers());

  describe("append", () => {
    it("appends new point to existing provider", async () => {
      vi.useFakeTimers();
      const { createHistoryStore } = await loadHistory();
      const s = createHistoryStore("/fake.json", { ...deps(), now: () => NOW });
      const p = s.append("openai", { timestamp: NOW, used: 90, limit: 100 });
      await vi.advanceTimersByTimeAsync(5100); await p;
      const w = JSON.parse(mockWrite.mock.calls.at(-1)?.[1] as string);
      expect(w.history.openai.at(-1)).toMatchObject({ timestamp: NOW, used: 90, limit: 100 });
    });
    it("creates new provider entry", async () => {
      vi.useFakeTimers();
      const { createHistoryStore } = await loadHistory();
      const s = createHistoryStore("/fake.json", { ...deps(), now: () => NOW });
      const p = s.append("newprov", { timestamp: NOW, used: 50, limit: 200 });
      await vi.advanceTimersByTimeAsync(5100); await p;
      expect(JSON.parse(mockWrite.mock.calls.at(-1)?.[1] as string).history.newprov).toHaveLength(1);
    });
  });

  describe("reset detection (≥20% drop)", () => {
    it.each([
      { used: 60, limit: 100, desc: "≥20% drop → clears history", expectLen: 1 },
      { used: 75, limit: 100, desc: "<20% drop → retains history", expectLen: 6 },
      { used: 95, limit: 100, desc: "increase → retains history", expectLen: 6 },
    ])("$desc", async ({ used, limit, expectLen }) => {
      vi.useFakeTimers();
      const { createHistoryStore } = await loadHistory();
      const s = createHistoryStore("/fake.json", { ...deps(), now: () => NOW });
      const p = s.append("openai", { timestamp: NOW, used, limit });
      await vi.advanceTimersByTimeAsync(5100); await p;
      const w = JSON.parse(mockWrite.mock.calls.at(-1)?.[1] as string);
      expect(w.history.openai).toHaveLength(expectLen);
    });
  });

  describe("getHistory", () => {
    it("returns points within window", async () => {
      vi.useFakeTimers();
      const { createHistoryStore } = await loadHistory();
      const h = await createHistoryStore("/fake.json", { ...deps(), now: () => NOW }).getHistory("openai", 2 * 60 * 60 * 1000);
      expect(h.length).toBeGreaterThanOrEqual(1);
    });
    it("returns empty for unknown provider", async () => {
      const { createHistoryStore } = await loadHistory();
      const h = await createHistoryStore("/fake.json", deps()).getHistory("unknown", 60 * 60 * 1000);
      expect(h).toHaveLength(0);
    });
  });

  describe("prune", () => {
    it("removes stale points", async () => {
      vi.useFakeTimers();
      const { createHistoryStore } = await loadHistory();
      await createHistoryStore("/fake.json", { ...deps(), now: () => NOW }).prune(10 * 60 * 1000);
      expect(mockWrite).toHaveBeenCalled();
    });
  });

  describe("debounced save", () => {
    it("does not write immediately after append", async () => {
      vi.useFakeTimers();
      const { createHistoryStore } = await loadHistory();
      const s = createHistoryStore("/fake.json", { ...deps(), now: () => NOW });
      const p = s.append("openai", { timestamp: NOW, used: 90, limit: 100 });
      expect(mockWrite).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(5100); await p;
      expect(mockWrite).toHaveBeenCalled();
    });
  });
});
