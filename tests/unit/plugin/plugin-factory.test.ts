// WU-6 RED: plugin factory returns empty Hooks (no footer subscription).
// REQ-REM-1..7: src/plugin/index.ts must NOT subscribe to experimental.text.complete.
import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";

// Mock config loader and credential resolver so plugin factory can boot without real files
vi.mock("../../../src/adapters/infra/config-loader.js", () => ({
  DEFAULTS: { displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5, showUnaggregated: false, progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false } },
  loadConfig: vi.fn(() => ({ displayMode: "table", disabled: [], aggregatedGroups: {}, historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5, showUnaggregated: false, progressBar: { width: 20, filledChar: "█", emptyChar: "░", color: true, gradients: false } })),
}));

vi.mock("../../../src/adapters/auth/credential-resolver.js", () => ({
  createCredentialResolver: vi.fn(() => ({ get: () => Promise.resolve(null) })),
}));

vi.mock("../../../src/adapters/infra/fetch-http.js", () => ({
  FetchHttpClient: vi.fn(() => ({ request: vi.fn() })),
}));

describe("Plugin factory", () => {
  it("returns empty Hooks (no experimental.text.complete subscription)", async () => {
    const pluginFactory = (await import("../../../src/plugin/index.js")).default;
    const hooks = await pluginFactory({ directory: "/tmp" });
    // After WU-6, the plugin must NOT subscribe to experimental.text.complete
    expect(hooks).toEqual({});
  });
});
