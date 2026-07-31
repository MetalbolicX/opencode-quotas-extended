// Provider registry — Map<providerId, QuotaProvider>.
import type { CredentialSource } from "../../ports/credentials.js";
import type { HttpClient } from "../../ports/http.js";
import type { Logger } from "../../ports/logger.js";
import type { QuotaProvider } from "../../ports/provider.js";
import { createOpenAIProvider } from "./openai.js";
import { createZenProvider } from "./zen.js";
import { createGoProvider } from "./go.js";
import { createZaiProvider } from "./zai.js";
import { createKimiProvider } from "./kimi.js";
import { createMinimaxProvider } from "./minimax.js";
import { createAnthropicProvider } from "./anthropic.js";
import { createGeminiProvider } from "./gemini.js";

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

// buildDefaultRegistry — registers all 8 providers.
// logger is optional; when absent, factories use a silent noop internally.
export function buildDefaultRegistry(
  credentialSource: CredentialSource,
  http: HttpClient,
  logger?: Logger,
): ProviderRegistry {
  const registry = createProviderRegistry();
  registry.register(createOpenAIProvider(credentialSource, http, logger));
  registry.register(createZenProvider(credentialSource, http, logger));
  registry.register(createGoProvider(credentialSource, http, logger));
  registry.register(createZaiProvider(credentialSource, http, logger));
  registry.register(createKimiProvider(credentialSource, http, logger));
  registry.register(createMinimaxProvider(credentialSource, http, logger));
  registry.register(createAnthropicProvider(credentialSource, http, undefined, undefined, undefined, logger));
  registry.register(createGeminiProvider(credentialSource, http, logger));
  return registry;
}
