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

  it("command body must not pass user input verbatim to shell", () => {
    const content = readFileSync(COMMAND_PATH, "utf-8");
    // If $ARGUMENTS or similar user-input interpolation appears, it must NOT be inside a shell string
    // The design requires NO user shell interpolation — only fixed command
    // Reject patterns like: `opencode-quotas $ARGUMENTS` or `$(echo $ARGUMENTS)`
    const userShellInterp = /\$ARGUMENTS|\$\{ARGUMENTS\}|\$\(\s*echo\s+\$/;
    expect(content, "command must not interpolate user input into shell").not.toMatch(userShellInterp);
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
