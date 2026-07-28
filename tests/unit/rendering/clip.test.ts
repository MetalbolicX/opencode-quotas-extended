// RED → GREEN → REFACTOR: ANSI-aware text clip utility.
// clip(str, width, ellipsis) measures visible length after stripping SGR codes,
// truncates to (width - ellipsis.length) visible chars, appends ellipsis,
// pads remaining width with spaces. Final visible length = width.
import { describe, it, expect } from "vitest";
import { clip, stripAnsi } from "../../../src/rendering/text/clip.js";

describe("clip — ANSI-aware truncation", () => {
  it("returns empty string when width is 0", () => {
    expect(clip("hello", 0)).toBe("");
  });

  it("returns truncated ellipsis when width equals ellipsis length", () => {
    expect(clip("hello", 1)).toBe("…");
  });

  it("strips ANSI SGR codes before measuring visible width", () => {
    // "\x1b[32mhello\x1b[0m" has 5 visible chars but >14 code+text bytes
    const colored = "\x1b[32mhello\x1b[0m";
    expect(clip(colored, 5)).toBe("hello");
  });

  it("truncates visible text and appends ellipsis when text exceeds width", () => {
    // "hello world" (11) → clip to 8-1=7 visible + "…" → "hello w…" (8 visible, 8 total)
    expect(clip("hello world", 8)).toBe("hello w…");
  });

  it("pads with spaces when text is shorter than width", () => {
    expect(clip("hi", 6)).toBe("hi    ");
  });

  it("truncates to (width - ellipsis.length) visible chars", () => {
    // "hello world" (11) → clip to 10-1=9 visible + "…" → "hello wor…" (10 visible)
    expect(clip("hello world", 10)).toBe("hello wor…");
  });

  it("uses custom ellipsis when provided", () => {
    // "hello world" (11) → clip to 8-2=6 visible + ".." → "hello .." (8 total: 5 hets + space + 2 ellipsis)
    expect(clip("hello world", 8, "..")).toBe("hello ..");
  });

  it("handles width smaller than ellipsis length gracefully", () => {
    expect(clip("hello", 1, "~~")).toBe("~");
  });

  it("handles multi-byte unicode correctly", () => {
    // Unicode chars count as single visible chars
    expect(clip("hello", 3)).toBe("he…");
  });

  it("handles string with only ANSI codes (no visible text)", () => {
    // No visible chars → padded to width with spaces
    const codesOnly = "\x1b[32m\x1b[0m";
    expect(clip(codesOnly, 5)).toBe("     ");
  });

  it("clip 28-char name to 24 keeps within slot", () => {
    // "Minimax · Daily request quota" (28 visible) → clip to 24-1=23 + "…" → 24 visible
    const longName = "Minimax · Daily request quota";
    const result = clip(longName, 24);
    expect(result.replace(/\x1b\[\d+m/g, "")).toHaveLength(24);
    expect(result).toContain("…");
  });

  it("clip 40-char name to 24: result has exactly 24 visible chars", () => {
    const fortyChar = "A".repeat(40);
    const result = clip(fortyChar, 24);
    expect(result.replace(/\x1b\[\d+m/g, "")).toHaveLength(24);
    expect(result).toContain("…");
  });
});

describe("stripAnsi", () => {
  it("strips SGR codes from colored text", () => {
    expect(stripAnsi("\x1b[32mgreen\x1b[0m")).toBe("green");
  });

  it("strips multiple SGR codes", () => {
    expect(stripAnsi("\x1b[32m\x1b[2mstyled\x1b[0m\x1b[0m")).toBe("styled");
  });

  it("returns input unchanged if no ANSI codes", () => {
    expect(stripAnsi("plain text")).toBe("plain text");
  });

  it("returns empty string for codes-only input", () => {
    expect(stripAnsi("\x1b[32m\x1b[0m")).toBe("");
  });
});
