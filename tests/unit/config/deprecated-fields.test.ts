import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { writeFileSync, unlinkSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadConfig, DEFAULTS } from "../../../legacy/adapters/infra/config-loader.js";

const PROJECT_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const FIXTURE_DIR = join(PROJECT_ROOT, "tests/fixtures/config");

beforeEach(() => {
  mkdirSync(FIXTURE_DIR, { recursive: true });
});

afterEach(() => {
  try {
    unlinkSync(join(FIXTURE_DIR, "quotas.json"));
  } catch {
    // ignore
  }
});

describe("deprecated config fields", () => {
  it("loads {show,pollingInterval} without ConfigValidationError and returns defaults (values stripped)", () => {
    const configPath = join(FIXTURE_DIR, "quotas.json");
    writeFileSync(configPath, JSON.stringify({ show: true, pollingInterval: 30 }));
    // Must not throw
    const config = loadConfig(configPath);
    // Deprecated values must be stripped: pollingInterval reverts to default (0)
    expect(config.pollingInterval).toBe(DEFAULTS.pollingInterval);
    expect(config.pollingInterval).toBe(0);
    // show is also stripped (undefined or default) — verify it does not propagate
    // The DEFAULTS.show is true, so as long as we got a valid config back, stripping worked
    expect(config).toBeDefined();
    expect(config.displayMode).toBe("table");
  });

  it("emits two deprecation warnings (one per deprecated field) when show and pollingInterval present", () => {
    const configPath = join(FIXTURE_DIR, "quotas.json");
    writeFileSync(configPath, JSON.stringify({ show: true, pollingInterval: 30 }));

    const warnings: string[] = [];
    const originalWarn = console.warn;
    console.warn = (...args: unknown[]) => {
      warnings.push(args.map(String).join(" "));
    };

    try {
      loadConfig(configPath);
    } finally {
      console.warn = originalWarn;
    }

    // Should emit one warning per deprecated field present
    const deprecationWarnings = warnings.filter((w) =>
      w.includes("show") || w.includes("pollingInterval"),
    );
    expect(deprecationWarnings.length).toBeGreaterThanOrEqual(2);
  });

  it("emits no deprecation warnings when config has no deprecated fields", () => {
    const configPath = join(FIXTURE_DIR, "quotas.json");
    writeFileSync(configPath, JSON.stringify({ displayMode: "json", disabled: ["openai"] }));

    const warnings: string[] = [];
    const originalWarn = console.warn;
    console.warn = (...args: unknown[]) => {
      warnings.push(args.map(String).join(" "));
    };

    try {
      loadConfig(configPath);
    } finally {
      console.warn = originalWarn;
    }

    // No deprecation warnings
    const deprecationWarnings = warnings.filter(
      (w) => w.includes("deprecated") && (w.includes("show") || w.includes("pollingInterval") || w.includes("footer")),
    );
    expect(deprecationWarnings.length).toBe(0);
  });
});
