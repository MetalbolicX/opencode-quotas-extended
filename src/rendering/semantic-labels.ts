// WU-2: pure semantic label helpers for quota enrichment.
// Adapters own label resolution; renderer treats info as opaque.
export type QuotaConcept =
  | "z.ai-5-hour-rolling"
  | "z.ai-mcp"
  | "z.ai-token"
  | "minimax-daily-request"
  | "minimax-weekly-request"
  | "openai-primary-rate"
  | "openai-secondary-rate"
  | "openai-credits"
  | "openai-token-usage"
  | "gemini-model-quota";

export interface ProviderPayloadHints {
  readonly type?: string;        // z.ai row type
  readonly unit?: number | null;  // z.ai row unit
  readonly number?: number | null; // z.ai row count
  readonly modelName?: string;   // minimax model name
  readonly weekly?: boolean;     // minimax row context
  readonly openaiVariant?: "primary" | "secondary" | "credits" | "api";
  readonly geminiModel?: string;
}

// Label catalog — one entry per concept
const LABEL_MAP: Record<QuotaConcept, string> = {
  "z.ai-5-hour-rolling": "5-hour rolling limit",
  "z.ai-mcp": "MCP quota",
  "z.ai-token": "Token quota",
  "minimax-daily-request": "Daily request quota",
  "minimax-weekly-request": "Weekly request quota",
  "openai-primary-rate": "Primary rate limit",
  "openai-secondary-rate": "Secondary rate limit",
  "openai-credits": "Credit balance",
  "openai-token-usage": "Token usage",
  "gemini-model-quota": "Model quota",
};

/**
 * Resolves explicit payload fields to a canonical concept + human-readable label.
 * Pure / stateless — no I/O, no mutation.
 */
export function enrichQuotaLabel(
  _providerId: string,
  hints: ProviderPayloadHints,
): { label: string; concept: QuotaConcept } {
  // z.ai concepts
  if (hints.type === "TIME_LIMIT") {
    if (hints.unit === 5) return { label: LABEL_MAP["z.ai-5-hour-rolling"], concept: "z.ai-5-hour-rolling" };
    return { label: LABEL_MAP["z.ai-5-hour-rolling"], concept: "z.ai-5-hour-rolling" };
  }
  if (hints.type === "MCP_LIMIT") return { label: LABEL_MAP["z.ai-mcp"], concept: "z.ai-mcp" };
  if (hints.type === "TOKENS_LIMIT") return { label: LABEL_MAP["z.ai-token"], concept: "z.ai-token" };

  // minimax concepts
  if (hints.weekly) return { label: LABEL_MAP["minimax-weekly-request"], concept: "minimax-weekly-request" };
  if (hints.modelName !== undefined) return { label: LABEL_MAP["minimax-daily-request"], concept: "minimax-daily-request" };

  // openai concepts
  if (hints.openaiVariant === "primary") return { label: LABEL_MAP["openai-primary-rate"], concept: "openai-primary-rate" };
  if (hints.openaiVariant === "secondary") return { label: LABEL_MAP["openai-secondary-rate"], concept: "openai-secondary-rate" };
  if (hints.openaiVariant === "credits") return { label: LABEL_MAP["openai-credits"], concept: "openai-credits" };
  if (hints.openaiVariant === "api") return { label: LABEL_MAP["openai-token-usage"], concept: "openai-token-usage" };

  // gemini concept
  if (hints.geminiModel !== undefined) return { label: LABEL_MAP["gemini-model-quota"], concept: "gemini-model-quota" };

  // Fallback — return token usage concept to avoid empty strings
  return { label: LABEL_MAP["openai-token-usage"], concept: "openai-token-usage" };
}

/**
 * Builds a branded provider name: "<brand> · <label>".
 * Separator uses non-breaking space (U+00A0) around the middle dot.
 */
export function buildProviderName(brand: string, concept: QuotaConcept, model?: string): string {
  const label = LABEL_MAP[concept];
  if (concept === "gemini-model-quota" && model) {
    return `${brand}\u00A0·\u00A0${label} (${model})`;
  }
  return `${brand}\u00A0·\u00A0${label}`;
}
