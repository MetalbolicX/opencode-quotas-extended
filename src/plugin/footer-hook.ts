// Footer hook — mutates output.text by appending a compact quota footer.
// Guards: already processed, already pending, signature in text, non-text/last-part checks.
// Uses pluginState.acquireLock for concurrency safety.
import type { PluginState } from "./state.js";

export interface TextCompleteInput {
  sessionID: string;
  messageID: string;
  partID: string;
}

export interface TextCompleteOutput {
  text: string;
}

export interface FooterDeps {
  pluginState: PluginState;
  /** Returns the footer string to append. */
  renderFooter: () => Promise<string>;
  /** Signature string that marks "footer already present" in text. */
  signature: string;
}

/**
 * Handle the experimental.text.complete hook.
 *
 * Guards (skip footer injection when):
 * - messageID is already processed
 * - messageID is already pending (lock held by another caller)
 * - output.text already contains the footer signature
 *
 * When all guards pass, acquires a per-message lock, re-checks processed/pending,
 * appends the rendered footer to output.text, and marks the message processed.
 */
export async function handleTextComplete(
  input: TextCompleteInput,
  output: TextCompleteOutput,
  deps: FooterDeps,
): Promise<void> {
  const { pluginState, renderFooter, signature } = deps;
  const { messageID } = input;

  // Fast-path guards — before acquiring lock
  if (pluginState.isProcessed(messageID)) return;
  if (pluginState.isPending(messageID)) return;

  // Idempotency — if footer already in text, treat as processed
  if (output.text.includes(signature)) {
    pluginState.markProcessed(messageID);
    return;
  }

  // Acquire per-message lock to prevent double injection under concurrency
  const releaseLock = await pluginState.acquireLock(messageID);
  try {
    // Re-check after acquiring lock
    if (pluginState.isProcessed(messageID)) return;
    if (pluginState.isPending(messageID)) return;

    // Double-check footer content (another process may have injected while we waited)
    if (output.text.includes(signature)) {
      pluginState.markProcessed(messageID);
      return;
    }

    // Render the footer
    const footer = await renderFooter();

    // Append footer: output.text += "\n" + footer
    output.text = output.text + "\n" + footer;

    pluginState.markProcessed(messageID);
  } finally {
    await releaseLock();
  }
}
