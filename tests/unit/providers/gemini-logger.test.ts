// WU-4/5 RED: factory accepts optional Logger, gemini routes 6 warnings through it.
// REQ-LOG-1,2: all 8 factories accept optional logger?; buildDefaultRegistry threads it.
// REQ-LOG-3..6: gemini's 6 console.warn sites route through logger.warn.
import { describe, expect, it, vi } from "vitest";
import type { Logger } from "../../../legacy/ports/logger.js";
import { noopLogger } from "../../../legacy/ports/logger.js";

describe("Provider factory: optional Logger parameter", () => {
  describe("buildDefaultRegistry threads logger to all 8 factories", () => {
    it("buildDefaultRegistry accepts 3-arg call with logger", async () => {
      const { buildDefaultRegistry } = await import("../../../legacy/adapters/providers/registry.js");
      const fakeCred = { get: async () => null };
      const fakeHttp = { request: vi.fn() };
      const fakeLogger: Logger = { debug() {}, info() {}, warn() {}, error() {} };
      // Should not throw — 3-arg call with logger
      const r = buildDefaultRegistry(fakeCred as any, fakeHttp as any, fakeLogger);
      expect(r.list()).toHaveLength(8);
    });

    it("buildDefaultRegistry accepts 2-arg call (logger optional, defaults to noop)", async () => {
      const { buildDefaultRegistry } = await import("../../../legacy/adapters/providers/registry.js");
      const fakeCred = { get: async () => null };
      const fakeHttp = { request: vi.fn() };
      // Should not throw — 2-arg call without logger
      const r = buildDefaultRegistry(fakeCred as any, fakeHttp as any);
      expect(r.list()).toHaveLength(8);
    });
  });

  describe("gemini: console.warn routed through logger.warn", () => {
    it("no console.warn leak when noopLogger is injected", async () => {
      const consoleSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
      const { createGeminiProvider } = await import("../../../legacy/adapters/providers/gemini.js");
      const fakeCred = { get: async () => null };
      const fakeHttp = { request: vi.fn() };
      const provider = createGeminiProvider(fakeCred as any, fakeHttp as any, noopLogger);
      await provider.fetchQuotas();
      // With noopLogger, no console.warn should leak
      expect(consoleSpy).not.toHaveBeenCalled();
      consoleSpy.mockRestore();
    });

    it("mock Logger receives gemini.no-credential event", async () => {
      const warnMock = vi.fn();
      const mockLogger: Logger = { debug() {}, info() {}, warn: warnMock, error() {} };
      const { createGeminiProvider } = await import("../../../legacy/adapters/providers/gemini.js");
      const fakeCred = { get: async () => null };
      const fakeHttp = { request: vi.fn() };
      const provider = createGeminiProvider(fakeCred as any, fakeHttp as any, mockLogger);
      await provider.fetchQuotas();
      // No credential → should emit gemini.no-credential warning
      expect(warnMock).toHaveBeenCalledWith("gemini.no-credential", expect.any(Object));
    });

    it("gemini factory accepts optional logger as 3rd parameter", async () => {
      const { createGeminiProvider } = await import("../../../legacy/adapters/providers/gemini.js");
      const fakeCred = { get: async () => null };
      const fakeHttp = { request: vi.fn() };
      // 3-arg call with logger should not throw
      const p = createGeminiProvider(fakeCred as any, fakeHttp as any, noopLogger);
      expect(p.id).toBe("gemini");
    });
  });
});
