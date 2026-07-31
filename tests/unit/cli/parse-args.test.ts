// WU-4 RED: parseArgs with node:util.parseArgs — strict validation contract.
// These tests define the expected behavior BEFORE the implementation exists.
// Run: pnpm test tests/unit/cli/parse-args.test.ts
import { describe, it, expect } from "vitest";
import { parseArgs } from "../../../legacy/cli/parse-args.js";

describe("parseArgs", () => {
  // ── REQ-CLI-1: Default to list ──────────────────────────────────────────────
  it("parseArgs([]) → list:true", () => {
    expect(parseArgs([])).toMatchObject({ list: true });
  });

  // ── REQ-CLI-2: -l / --list ──────────────────────────────────────────────────
  it("parseArgs(['-l']) → list:true", () => {
    expect(parseArgs(["-l"])).toMatchObject({ list: true });
  });

  it("parseArgs(['--list']) → list:true", () => {
    expect(parseArgs(["--list"])).toMatchObject({ list: true });
  });

  // ── REQ-CLI-2: -p / --provider ─────────────────────────────────────────────
  it("parseArgs(['-p', 'openai']) → provider:openai", () => {
    expect(parseArgs(["-p", "openai"])).toMatchObject({ provider: "openai" });
  });

  it("parseArgs(['--provider', 'minimax']) → provider:minimax", () => {
    expect(parseArgs(["--provider", "minimax"])).toMatchObject({ provider: "minimax" });
  });

  // ── REQ-CLI-3: -c / --color ─────────────────────────────────────────────────
  it("parseArgs(['-c', 'green']) → color:green", () => {
    expect(parseArgs(["-c", "green"])).toMatchObject({ color: "green" });
  });

  it("parseArgs(['--color', 'red']) → color:red", () => {
    expect(parseArgs(["--color", "red"])).toMatchObject({ color: "red" });
  });

  // ── REQ-CLI-2: -m / --mode ──────────────────────────────────────────────────
  it("parseArgs(['-m', 'json']) → mode:json", () => {
    expect(parseArgs(["-m", "json"])).toMatchObject({ mode: "json" });
  });

  it("parseArgs(['-m', 'table']) → mode:table", () => {
    expect(parseArgs(["-m", "table"])).toMatchObject({ mode: "table" });
  });

  it("parseArgs(['-m', 'markdown']) → mode:markdown", () => {
    expect(parseArgs(["-m", "markdown"])).toMatchObject({ mode: "markdown" });
  });

  // ── -h / --help ────────────────────────────────────────────────────────────
  it("parseArgs(['-h']) → help:true", () => {
    expect(parseArgs(["-h"])).toMatchObject({ help: true });
  });

  it("parseArgs(['--help']) → help:true", () => {
    expect(parseArgs(["--help"])).toMatchObject({ help: true });
  });

  // ── REQ-CLI-4: Flag mutual exclusion ────────────────────────────────────────
  it("parseArgs(['-l', '-p', 'openai']) → throws 'cannot combine'", () => {
    expect(() => parseArgs(["-l", "-p", "openai"])).toThrow(/cannot combine/i);
  });

  it("parseArgs(['--list', '--provider', 'openai']) → throws 'cannot combine'", () => {
    expect(() => parseArgs(["--list", "--provider", "openai"])).toThrow(/cannot combine/i);
  });

  // ── REQ-CLI-3: Invalid color ─────────────────────────────────────────────────
  it("parseArgs(['-c', 'bogus']) → throws 'invalid color'", () => {
    expect(() => parseArgs(["-c", "bogus"])).toThrow(/invalid color/i);
  });

  it("parseArgs(['--color', 'turquoise']) → throws 'invalid color'", () => {
    expect(() => parseArgs(["--color", "turquoise"])).toThrow(/invalid color/i);
  });

  // ── REQ-CLI-2: Invalid mode ─────────────────────────────────────────────────
  it("parseArgs(['-m', 'xml']) → throws 'invalid mode'", () => {
    expect(() => parseArgs(["-m", "xml"])).toThrow(/invalid mode/i);
  });

  it("parseArgs(['-m', 'csv']) → throws 'invalid mode'", () => {
    expect(() => parseArgs(["-m", "csv"])).toThrow(/invalid mode/i);
  });

  // ── REQ-CLI-5: --no-color removed ───────────────────────────────────────────
  it("parseArgs(['--no-color']) → throws 'unknown option'", () => {
    expect(() => parseArgs(["--no-color"])).toThrow(/unknown option/i);
  });

  // ── Strict: unknown option ───────────────────────────────────────────────────
  it("parseArgs(['--bogus']) → throws 'unknown option'", () => {
    expect(() => parseArgs(["--bogus"])).toThrow(/unknown option/i);
  });

  it("parseArgs(['--unknown-flag']) → throws 'unknown option'", () => {
    expect(() => parseArgs(["--unknown-flag"])).toThrow(/unknown option/i);
  });

  // ── Default mode is table ───────────────────────────────────────────────────
  it("parseArgs([]) → mode:table", () => {
    expect(parseArgs([])).toMatchObject({ mode: "table" });
  });

  // ── Default help is false ───────────────────────────────────────────────────
  it("parseArgs([]) → help:false", () => {
    expect(parseArgs([])).toMatchObject({ help: false });
  });

  // ── Provider + mode combination is valid ────────────────────────────────────
  it("parseArgs(['-p', 'openai', '-m', 'json']) → provider+mode", () => {
    expect(parseArgs(["-p", "openai", "-m", "json"])).toMatchObject({ provider: "openai", mode: "json" });
  });

  // ── Color + mode combination is valid ──────────────────────────────────────
  it("parseArgs(['-c', 'cyan', '-m', 'markdown']) → color+mode", () => {
    expect(parseArgs(["-c", "cyan", "-m", "markdown"])).toMatchObject({ color: "cyan", mode: "markdown" });
  });
});
