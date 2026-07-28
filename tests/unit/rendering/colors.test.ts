// RED → GREEN: ANSI color name system for usage bar.
// Validates COLOR_MAP, isValidColor(), and ansiColor() contract.
import { describe, it, expect } from "vitest";

// ── dynamic imports resolved in beforeAll ──────────────────────────────────────

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let COLOR_MAP!: Readonly<Record<string, string>>;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let isValidColor!: (name: string) => boolean;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let ansiColor!: (name: string, text: string) => string;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let dim!: (text: string) => string;

beforeAll(async () => {
  const colors = await import("../../../src/rendering/colors.js");
  COLOR_MAP = colors.COLOR_MAP;
  isValidColor = colors.isValidColor;
  ansiColor = colors.ansiColor;
  dim = colors.dim;
});

const ALL_16_COLORS = [
  "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
  "brightBlack", "brightRed", "brightGreen", "brightYellow",
  "brightBlue", "brightMagenta", "brightCyan", "brightWhite",
] as const;

const ANSI_SGR_RANGE = /^\d{2}$/;

describe("COLOR_MAP", () => {
  it("is exported and defined", () => {
    expect(COLOR_MAP).toBeDefined();
  });

  it("contains all 16 expected color names", () => {
    for (const name of ALL_16_COLORS) {
      expect(COLOR_MAP).toHaveProperty(name);
    }
  });

  it("each value is a numeric string of an ANSI SGR code (30-37, 90-97)", () => {
    for (const name of ALL_16_COLORS) {
      const code = COLOR_MAP[name];
      expect(code).toMatch(ANSI_SGR_RANGE);
      const n = parseInt(code, 10);
      const valid = (n >= 30 && n <= 37) || (n >= 90 && n <= 97);
      expect(valid, `${name} → ${code} is not a valid SGR code`).toBe(true);
    }
  });
});

describe("isValidColor", () => {
  it("returns true for all 16 valid color names", () => {
    for (const name of ALL_16_COLORS) {
      expect(isValidColor(name)).toBe(true);
    }
  });

  it("returns false for invalid names", () => {
    const invalid = ["gray", "orange", "purple", "", "GREEN", " BrightRed "];
    for (const name of invalid) {
      expect(isValidColor(name)).toBe(false);
    }
  });

  it("is case-sensitive (only lowercase accepted)", () => {
    expect(isValidColor("GREEN")).toBe(false);
    expect(isValidColor("Green")).toBe(false);
    expect(isValidColor("RED")).toBe(false);
  });
});

describe("ansiColor", () => {
  it('"green" + "hello" wraps text in \\x1b[32m...\\x1b[0m', () => {
    const out = ansiColor("green", "hello");
    expect(out).toBe("\x1b[32mhello\x1b[0m");
  });

  it('"brightRed" + "warn" wraps text in \\x1b[91m...\\x1b[0m', () => {
    const out = ansiColor("brightRed", "warn");
    expect(out).toBe("\x1b[91mwarn\x1b[0m");
  });

  it('"blue" + "" produces empty ANSI-wrapped string', () => {
    const out = ansiColor("blue", "");
    expect(out).toBe("\x1b[34m\x1b[0m");
  });

  it("throws Error for invalid color name", () => {
    expect(() => ansiColor("gray", "test")).toThrow(Error);
    expect(() => ansiColor("", "test")).toThrow(Error);
    expect(() => ansiColor("GREEN", "test")).toThrow(Error);
  });

  it("error message lists valid color names", () => {
    try {
      ansiColor("gray", "test");
    } catch (e) {
      expect((e as Error).message).toMatch(/Invalid color name/);
    }
  });
});

describe("ansiColor integration — colored usage bar", () => {
  it("wraps a 10-character bar in green ANSI codes", () => {
    const bar = "█".repeat(10);
    const colored = ansiColor("green", bar);
    // "\x1b[32m" = 5 chars (1 esc + 1 [ + 2 digits + 1 m), "\x1b[0m" = 4 chars
    expect(colored).toBe("\x1b[32m" + bar + "\x1b[0m");
    expect(colored.length).toBe(5 + bar.length + 4);
  });

  it("bright colors produce visually distinct output", () => {
    const dimColored = ansiColor("red", "X");
    const bright = ansiColor("brightRed", "X");
    expect(dimColored).not.toBe(bright);
    expect(dimColored).toMatch(/^\x1b\[3\dmX\x1b\[0m$/);
    expect(bright).toMatch(/^\x1b\[9\dmX\x1b\[0m$/);
  });
});

describe("dim", () => {
  it("wraps text in SGR 2 + reset", () => {
    expect(dim("foo")).toBe("\x1b[2mfoo\x1b[0m");
  });

  it("returns empty string for empty input", () => {
    expect(dim("")).toBe("\x1b[2m\x1b[0m");
  });
});
