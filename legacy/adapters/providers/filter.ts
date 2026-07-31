// filterAvailableProviders — shared availability filter for CLI and plugin.
// D-3: extracted from src/plugin/index.ts.
// Uses Promise.allSettled so one provider's isAvailable() failure is isolated.
import type { QuotaProvider } from "../../ports/provider.js";

/**
 * Filters a provider list to only those where isAvailable() returns true.
 * Uses Promise.allSettled so one provider's isAvailable() failure is isolated
 * and does not prevent other providers from being queried.
 * Provider ordering is preserved.
 */
export async function filterAvailableProviders(
  providers: QuotaProvider[],
): Promise<QuotaProvider[]> {
  const settled = await Promise.allSettled(
    providers.map(async (p) => {
      // Port interface: isAvailable(credentials, ctx). All providers override with 0-arg
      // signatures; pass undefined/{} to satisfy the contract at the call site.
      const available = await (p as unknown as { isAvailable(): Promise<boolean> }).isAvailable();
      return { provider: p, available };
    }),
  );

  const available: QuotaProvider[] = [];
  for (const result of settled) {
    if (result.status === "fulfilled" && result.value.available) {
      available.push(result.value.provider);
    }
  }
  return available;
}
