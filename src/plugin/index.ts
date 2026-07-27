// Plugin entry — satisfies opencode Plugin type.
// D-8: Footer and state machine removed. Plugin returns empty Hooks.
// The /check-quotas command (CLI --list picker) replaces the old auto-footer behavior.
// DEP-6 REM-1..7: no experimental.text.complete subscription.
import type { Hooks, Plugin } from "@opencode-ai/plugin";

export default (async (_opts: { directory: string }): Promise<Hooks> => {
  return {};
}) satisfies Plugin;
