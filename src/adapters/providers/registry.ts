// Provider registry — Map<providerId, QuotaProvider>.
import type { QuotaProvider } from "../../ports/provider.js";

export interface ProviderRegistry {
  register(p: QuotaProvider): void;
  get(id: string): QuotaProvider | undefined;
  list(): QuotaProvider[];
}

export function createProviderRegistry(): ProviderRegistry {
  const map = new Map<string, QuotaProvider>();
  return {
    register(p: QuotaProvider) { map.set(p.id, p); },
    get(id: string) { return map.get(id); },
    list() { return Array.from(map.values()); },
  };
}
