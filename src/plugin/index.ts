// Plugin entry — satisfies opencode Plugin type.
// Returns { 'experimental.text.complete': handleTextComplete }.
import type { Plugin } from "@opencode-ai/plugin";
import { handleTextComplete } from "./footer-hook.js";
import { PluginState } from "./state.js";
import { loadConfig } from "../adapters/infra/config-loader.js";
import { existsSync } from "node:fs";
import { join } from "node:path";

/** Default footer signature — marks "footer already injected" in output.text */
const FOOTER_SIGNATURE = "<!-- quota-footer -->";

export default (async ({ client, $, directory }) => {
  // Simple injectable clock using Date.now
  const clock = () => Date.now();
  const pluginState = new PluginState(clock);

  // Load quotas config to read the show field (tri-state: simple|detailed|hidden)
  // show: false = hidden (no footer), show: true | undefined = show (compact footer)
  // displayMode (table|json|markdown) is orthogonal and controls /quotas output format.
  const configPath = join(directory, ".opencode", "quotas.json");
  const config = existsSync(configPath) ? loadConfig(configPath) : { show: true };

  /**
   * Renders the quota footer via the CLI.
   * Slice 9 wires this to the real opencode-quotas CLI.
   * For now returns a stub to satisfy the interface.
   */
  async function renderFooter(): Promise<string> {
    // TODO(slice-9): invoke opencode-quotas CLI via $ or client
    return "```text\nquota: stub (CLI wiring in slice-9)\n```";
  }

  const deps = {
    pluginState,
    renderFooter,
    signature: FOOTER_SIGNATURE,
    show: config.show,
  };

  return {
    "experimental.text.complete": async (
      input: { sessionID: string; messageID: string; partID: string },
      output: { text: string },
    ) => {
      await handleTextComplete(input, output, deps);
    },
  };
}) satisfies Plugin;
