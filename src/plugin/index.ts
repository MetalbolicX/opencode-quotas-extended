// Plugin entry — satisfies opencode Plugin type.
// Returns { 'experimental.text.complete': handleTextComplete }.
import type { Plugin } from "@opencode-ai/plugin";
import { handleTextComplete } from "./footer-hook.js";
import { PluginState } from "./state.js";

/** Default footer signature — marks "footer already injected" in output.text */
const FOOTER_SIGNATURE = "<!-- quota-footer -->";

export default (async ({ client, $, directory }) => {
  // Simple injectable clock using Date.now
  const clock = () => Date.now();
  const pluginState = new PluginState(clock);

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
