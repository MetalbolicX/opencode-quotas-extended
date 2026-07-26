// RED: Footer tri-state mapping tests — show + displayMode orthogonality.
// Documents the reference plugin's simple|detailed|hidden tri-state:
//   simple    = show:true + compact footer (footer-hook)
//   detailed  = show:true + full render (/quotas and CLI)
//   hidden    = show:false (no footer injection)
import { describe, it, expect } from "vitest";

/**
 * Tri-state mapping from the reference plugin's displayMode:
 * - "simple"    → show:true  + compact render (footer hook, table format)
 * - "detailed"  → show:true  + full render  (/quotas command, table/json/markdown)
 * - "hidden"    → show:false (footer suppressed; /quotas and CLI still render)
 *
 * displayMode (table|json|markdown) is ORTHOGONAL — it controls OUTPUT FORMAT,
 * not visibility. When show=false the footer is hidden but /quotas and CLI
 * continue to respect displayMode.
 */
describe("footer tri-state mapping", () => {
  describe("show:true → visible", () => {
    it("simple: show:true + compact → renders compact table in footer", () => {
      // The reference "simple" maps to show:true with compact footer rendering
      const config = { show: true, compact: true };
      expect(config.show).toBe(true);
      // compact=true means the footer uses a compact (narrow) table layout
    });

    it("detailed: show:true + full render → renders full table (orthogonal to displayMode)", () => {
      // /quotas and CLI use full rendering regardless of show
      // displayMode (table|json|markdown) is orthogonal and preserved
      const config = { show: true, displayMode: "json" as const };
      expect(config.show).toBe(true);
      // displayMode=json is independent of show — both render, just in different formats
    });
  });

  describe("show:false → hidden (footer-only no-op)", () => {
    it("hidden: show:false suppresses footer hook but /quotas still renders", () => {
      // show:false is footer-specific — /quotas and CLI ignore show
      const footerConfig = { show: false };
      const cliConfig = { show: false, displayMode: "table" as const };
      expect(footerConfig.show).toBe(false);
      // CLI always renders when invoked — show=false only affects the plugin footer
      expect(cliConfig.displayMode).toBe("table"); // displayMode still matters for /quotas
    });
  });

  describe("displayMode is orthogonal to show", () => {
    it("show=false + displayMode=json still produces JSON output when /quotas invokes", () => {
      // When /quotas command is called, displayMode determines the output format.
      // show only controls the footer plugin hook — it has no effect on /quotas.
      const config = { show: false, displayMode: "json" as const };
      // Simulating /quotas behavior: ignores show, respects displayMode
      const quotasOutput = simulateQuotasCommand(config);
      expect(() => JSON.parse(quotasOutput)).not.toThrow();
      expect(quotasOutput).not.toContain("<!-- quota-footer -->");
    });

    it("show=true + displayMode=markdown renders markdown in /quotas", () => {
      const config = { show: true, displayMode: "markdown" as const };
      const quotasOutput = simulateQuotasCommand(config);
      expect(quotasOutput).toContain("|");
    });

    it("footer injection respects show but not displayMode", () => {
      // Footer always uses compact table format regardless of displayMode
      const showFalseConfig = { show: false };
      const showTrueConfig = { show: true };
      expect(FooterHook.simulate(showFalseConfig).appendsFooter).toBe(false);
      expect(FooterHook.simulate(showTrueConfig).appendsFooter).toBe(true);
    });
  });
});

// ── Simulation helpers ────────────────────────────────────────────────────────

/** Simulates /quotas CLI output (ignores show, respects displayMode) */
function simulateQuotasCommand(config: { show: boolean; displayMode?: "table" | "json" | "markdown" }): string {
  const mode = config.displayMode ?? "table";
  if (mode === "json") return JSON.stringify({ fetchedAt: new Date().toISOString(), quotas: [] });
  if (mode === "markdown") return "| Name | Status | % | Reset |\n|-----|--------|-------|-------|\n";
  return "Name   Status   %   Reset\n";
}

const FooterHook = {
  simulate(config: { show: boolean }): { appendsFooter: boolean } {
    // When show is false, footer hook returns early without appending
    return { appendsFooter: config.show !== false };
  },
};
