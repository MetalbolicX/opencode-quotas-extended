import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const COMMAND_PATH = join(PROJECT_ROOT, "commands/check-quotas.md");

describe("/check-quotas command", () => {
  it("command file must exist", () => {
    expect(() => readFileSync(COMMAND_PATH, "utf-8")).not.toThrow();
  });

  it("command body must be data-only (no shell interpolation or executable content)", () => {
    const content = readFileSync(COMMAND_PATH, "utf-8");
    // The command body must NOT contain shell metacharacters that could execute arbitrary code
    const dangerous = [
      /\$\(/,           // command substitution
      /`[^`]+`/,       // backtick substitution
      /\|\s*(cat|sh|bash|exec|eval)/i,  // pipes to shells
      /;\s*(rm|del)/i, // command chaining with destructive commands
      /&&\s*(curl|wget)/i, // logical AND with download
      /\|\s*(curl|wget)/i, // pipe to download
    ];
    for (const re of dangerous) {
      expect(content, `command must not contain: ${re}`).not.toMatch(re);
    }
  });

  it("command body must invoke the fixed opencode-quotas CLI with --no-color", () => {
    const content = readFileSync(COMMAND_PATH, "utf-8");
    // The body (below frontmatter) must include the fixed CLI invocation
    expect(content).toContain("opencode-quotas");
    expect(content).toContain("--no-color");
  });

  it("command body must not pass user input verbatim to shell (dangerous patterns rejected)", () => {
    const content = readFileSync(COMMAND_PATH, "utf-8");
    // The design constrains $ARGUMENTS to ONLY appear inside --provider "$ARGUMENTS"
    // Reject dangerous patterns: command substitution, backtick sub, shell pipes, destructive chaining
    const dangerous = [
      /\$\([^(]/,           // command substitution (but allow $() for subshell with fixed cmd)
      /`[^`]+`/,           // backtick substitution
      /\|\s*(cat|sh|bash|exec|eval)/i,  // pipes to shells
      /;\s*(rm|del)/i, // command chaining with destructive commands
      /&&\s*(curl|wget)/i, // logical AND with download
      /\|\s*(curl|wget)/i, // pipe to download
    ];
    for (const re of dangerous) {
      expect(content, `command must not contain: ${re}`).not.toMatch(re);
    }
  });

  it("$ARGUMENTS must appear exactly once, inside double-quoted --provider flag", () => {
    const content = readFileSync(COMMAND_PATH, "utf-8");
    // $ARGUMENTS is permitted ONLY inside --provider "$ARGUMENTS"
    const argMatch = content.match(/--provider\s+"\$\{?ARGUMENTS\}?"/g);
    expect(argMatch, "body must contain --provider \"$ARGUMENTS\" (double-quoted, anchored to flag)").toHaveLength(1);
  });

  it("no-args path invokes opencode-quotas --no-color --list", () => {
    const content = readFileSync(COMMAND_PATH, "utf-8");
    expect(content).toContain("opencode-quotas --no-color --list");
  });

  it("no-args path asks the Spanish picker follow-up question", () => {
    const content = readFileSync(COMMAND_PATH, "utf-8");
    const spanishQuestion = "¿Querés ver el detalle de alguno? Respondé con el número o ID (o 'all' para mantener esta vista).";
    expect(content).toContain(spanishQuestion);
  });

  it("command file must have valid frontmatter", () => {
    const content = readFileSync(COMMAND_PATH, "utf-8");
    expect(content.trim()).toMatch(/^---/);
    const frontmatterEnd = content.indexOf("---", 3);
    expect(frontmatterEnd).toBeGreaterThan(0);
    const frontmatter = content.slice(0, frontmatterEnd + 3);
    expect(frontmatter).toContain("description");
  });
});
