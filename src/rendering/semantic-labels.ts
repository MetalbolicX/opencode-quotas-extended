// WU-2: pure semantic label helpers for quota enrichment.
// Adapters own label resolution; renderer treats info as opaque.
export type QuotaConcept =
  | "z.ai-5-hour-rolling"
  | "z.ai-mcp"
  | "z.ai-token"
  | "minimax-daily-request"
  | "minimax-weekly-request"
  | "minimax-5h-window"
  | "minimax-video"
  | "z.ai-weekly-rolling"
  | "z.ai-generic-rolling"
  | "openai-primary-rate"
  | "openai-secondary-rate"
  | "openai-credits"
  | "openai-token-usage"
  | "gemini-model-quota";

export interface ProviderPayloadHints {
  readonly type?: string;              // z.ai row type
  readonly unit?: number | string | null; // z.ai row unit (number or "weekly")
  readonly number?: number | null;     // z.ai row count
  readonly modelName?: string;         // minimax model name
  readonly weekly?: boolean;           // minimax row context
  readonly openaiVariant?: "primary" | "secondary" | "credits" | "api";
  readonly geminiModel?: string;
}

// Label catalog — one entry per concept
const LABEL_MAP: Record<QuotaConcept, string> = {
  "z.ai-5-hour-rolling": "5h quota",
  "z.ai-mcp": "MCP quota",
  "z.ai-token": "Token quota",
  "minimax-daily-request": "Daily request quota",
  "minimax-weekly-request": "Weekly limit",
  "minimax-5h-window": "5h rolling limit",
  "minimax-video": "Video generation",
  "z.ai-weekly-rolling": "Weekly quota",
  "z.ai-generic-rolling": "Generic rolling limit",
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
  // z.ai TIME_LIMIT — unit branching
  if (hints.type === "TIME_LIMIT") {
    const u = hints.unit;
    if (u === 5) {
      return { label: LABEL_MAP["z.ai-5-hour-rolling"], concept: "z.ai-5-hour-rolling" };
    }
    if (u === "weekly" || (typeof u === "number" && u >= 168)) {
      return { label: LABEL_MAP["z.ai-weekly-rolling"], concept: "z.ai-weekly-rolling" };
    }
    // Generic fallback: dynamic "{unit}-hour rolling limit"
    const unitVal = typeof u === "number" ? String(u) : "?";
    const concept: QuotaConcept = "z.ai-generic-rolling";
    const label = `${unitVal}-hour rolling limit`;
    return { label, concept };
  }
  if (hints.type === "MCP_LIMIT") return { label: LABEL_MAP["z.ai-mcp"], concept: "z.ai-mcp" };
  if (hints.type === "TOKENS_LIMIT") {
    // Distinguish multiple token limits by their `number` field so they don't collapse
    // into identical rows in the table (Z.AI can expose several token buckets).
    const base = LABEL_MAP["z.ai-token"];
    const discriminator = hints.number !== null && hints.number !== undefined ? ` #${hints.number}` : "";
    return { label: `${base}${discriminator}`, concept: "z.ai-token" };
  }

  // minimax concepts — weekly wins
  if (hints.weekly) {
    return { label: LABEL_MAP["minimax-weekly-request"], concept: "minimax-weekly-request" };
  }
  // Normalize modelName precedence: general→5h, video→video, default→legacy daily
  if (hints.modelName !== undefined) {
    if (hints.modelName === "general") {
      return { label: LABEL_MAP["minimax-5h-window"], concept: "minimax-5h-window" };
    }
    if (hints.modelName === "video") {
      return { label: LABEL_MAP["minimax-video"], concept: "minimax-video" };
    }
    return { label: LABEL_MAP["minimax-daily-request"], concept: "minimax-daily-request" };
  }

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
 * @param labelOverride - When provided, uses this label instead of the LABEL_MAP entry
 *                       (enables dynamic fallback text for non-cached concepts).
 */
export function buildProviderName(
  brand: string,
  concept: QuotaConcept,
  model?: string,
  labelOverride?: string,
): string {
  const label = labelOverride ?? LABEL_MAP[concept];
  if (concept === "gemini-model-quota" && model) {
    return `${brand}\u00A0·\u00A0${label} (${model})`;
  }
  return `${brand}\u00A0·\u00A0${label}`;
}
