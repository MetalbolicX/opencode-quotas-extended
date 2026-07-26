import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { writeFileSync, unlinkSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadConfig, ConfigValidationError } from "../../../src/adapters/infra/config-loader.js";

const PROJECT_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const FIXTURE_DIR = join(PROJECT_ROOT, "tests/fixtures/config");

let tmpDir: string;

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

describe("loadConfig", () => {
  it("returns defaults when config file does not exist", () => {
    const config = loadConfig(join(FIXTURE_DIR, "nonexistent.json"));
    expect(config.displayMode).toBe("table");
    expect(config.disabled).toEqual([]);
    expect(config.historyMaxAgeHours).toBe(24);
    expect(config.pollingInterval).toBe(0);
  });

  it("parses and returns a valid config", () => {
    const configPath = join(FIXTURE_DIR, "quotas.json");
    writeFileSync(configPath, JSON.stringify({
      displayMode: "json",
      disabled: ["openai"],
      historyMaxAgeHours: 48,
      pollingInterval: 300,
    }));
    const config = loadConfig(configPath);
    expect(config.displayMode).toBe("json");
    expect(config.disabled).toEqual(["openai"]);
    expect(config.historyMaxAgeHours).toBe(48);
    expect(config.pollingInterval).toBe(300);
  });

  it("throws ConfigValidationError for invalid config", () => {
    const configPath = join(FIXTURE_DIR, "quotas.json");
    writeFileSync(configPath, JSON.stringify({
      displayMode: "invalid-mode",
      unknownField: "should-not-exist",
    }));
    expect(() => loadConfig(configPath)).toThrow(ConfigValidationError);
  });

  it("throws ConfigValidationError with clear message on unknown key", () => {
    const configPath = join(FIXTURE_DIR, "quotas.json");
    writeFileSync(configPath, JSON.stringify({
      displayMode: "table",
      notARealField: true,
    }));
    expect(() => loadConfig(configPath)).toThrow(/notARealField|additional|invalid/i);
  });

  it("throws ConfigValidationError on wrong type for displayMode", () => {
    const configPath = join(FIXTURE_DIR, "quotas.json");
    writeFileSync(configPath, JSON.stringify({
      displayMode: 123,
    }));
    expect(() => loadConfig(configPath)).toThrow(ConfigValidationError);
  });

  it("merges defaults with partial config", () => {
    const configPath = join(FIXTURE_DIR, "quotas.json");
    writeFileSync(configPath, JSON.stringify({
      displayMode: "markdown",
    }));
    const config = loadConfig(configPath);
    expect(config.displayMode).toBe("markdown");
    expect(config.historyMaxAgeHours).toBe(24); // default
    expect(config.pollingInterval).toBe(0); // default
  });
});
