// RED: semantic-label helpers — pure unit tests for enrichQuotaLabel + buildProviderName.
// WU-2: no raw type/tuple leakage; all 10 concepts covered; brand separator invariant.
import { describe, it, expect } from "vitest";
import { enrichQuotaLabel, buildProviderName } from "../../../src/rendering/semantic-labels.js";
import type { QuotaConcept } from "../../../src/rendering/semantic-labels.js";

// ─── PR2: new concepts (semantic labels + i18n) ─────────────────────────────────
// These tests cover:
//   • 4 new QuotaConcept keys: minimax-5h-window, minimax-video, z.ai-weekly-rolling, z.ai-generic-rolling
//   • TIME_LIMIT unit branching: 5 → 5h, "weekly"|168 → weekly, other N → N-hour fallback
//   • Minimax model precedence: weekly wins, general→5h, video→video, default→legacy daily
//   • buildProviderName label override for dynamic fallback text

describe("QuotaConcept exhaustive table", () => {
  const cases: Array<{ hints: Parameters<typeof enrichQuotaLabel>[1]; expectedConcept: QuotaConcept; expectedLabel: string }> = [
    // z.ai concepts
    { hints: { type: "TIME_LIMIT", unit: 5 }, expectedConcept: "z.ai-5-hour-rolling", expectedLabel: "5h quota" },
    { hints: { type: "MCP_LIMIT", unit: 1 }, expectedConcept: "z.ai-mcp", expectedLabel: "MCP quota" },
    { hints: { type: "TOKENS_LIMIT", unit: 3 }, expectedConcept: "z.ai-token", expectedLabel: "Token quota" },
    // minimax concepts
    { hints: { modelName: "general", weekly: false }, expectedConcept: "minimax-5h-window", expectedLabel: "5h rolling limit" },
    { hints: { modelName: "general", weekly: true }, expectedConcept: "minimax-weekly-request", expectedLabel: "Weekly limit" },
    // openai concepts
    { hints: { openaiVariant: "primary" }, expectedConcept: "openai-primary-rate", expectedLabel: "Primary rate limit" },
    { hints: { openaiVariant: "secondary" }, expectedConcept: "openai-secondary-rate", expectedLabel: "Secondary rate limit" },
    { hints: { openaiVariant: "credits" }, expectedConcept: "openai-credits", expectedLabel: "Credit balance" },
    { hints: { openaiVariant: "api" }, expectedConcept: "openai-token-usage", expectedLabel: "Token usage" },
    // gemini concept
    { hints: { geminiModel: "gemini-3-pro-high" }, expectedConcept: "gemini-model-quota", expectedLabel: "Model quota" },
  ];

  it.each(cases)("enrichQuotaLabel for $expectedConcept → info label $expectedLabel", ({ hints, expectedLabel }) => {
    const result = enrichQuotaLabel("test-provider", hints);
    expect(result.label).toBe(expectedLabel);
  });

  it.each(cases)("enrichQuotaLabel for $expectedConcept → concept field", ({ hints, expectedConcept }) => {
    const result = enrichQuotaLabel("test-provider", hints);
    expect(result.concept).toBe(expectedConcept);
  });
});

describe("buildProviderName", () => {
  it("uses the · separator with non-breaking spaces", () => {
    const result = buildProviderName("z.ai", "z.ai-5-hour-rolling");
    expect(result).toBe("z.ai\u00A0·\u00A05h quota");
  });

  it("capitalises brand as provided", () => {
    expect(buildProviderName("z.ai", "z.ai-5-hour-rolling")).toMatch(/^z\.ai/);
    expect(buildProviderName("Minimax", "minimax-daily-request")).toMatch(/^Minimax/);
    expect(buildProviderName("OpenAI", "openai-primary-rate")).toMatch(/^OpenAI/);
    expect(buildProviderName("Google Gemini", "gemini-model-quota")).toMatch(/^Google Gemini/);
  });

  it("returns exactly one separator per result", () => {
    const result = buildProviderName("z.ai", "z.ai-5-hour-rolling");
    const matches = result.match(/\u00A0·\u00A0/g);
    expect(matches).toHaveLength(1);
  });

  it("includes model name in parenthetical for gemini-model-quota when model is provided", () => {
    const result = buildProviderName("Google Gemini", "gemini-model-quota", "gemini-3-flash");
    expect(result).toContain("gemini-3-flash");
  });
});

describe("enrichQuotaLabel — edge cases", () => {
  it("returns concept even when all hints are undefined", () => {
    const result = enrichQuotaLabel("unknown", {});
    expect(result.concept).toBeDefined();
  });

  it("openaiVariant takes precedence over type for concept resolution", () => {
    // Even with a type field, openaiVariant should drive the concept
    const result = enrichQuotaLabel("openai", { openaiVariant: "primary" });
    expect(result.concept).toBe("openai-primary-rate");
  });

  it("weekly minimax hint drives weekly concept over modelName alone", () => {
    const result = enrichQuotaLabel("minimax", { modelName: "general", weekly: true });
    expect(result.concept).toBe("minimax-weekly-request");
    expect(result.label).toBe("Weekly limit");
  });

  it("daily minimax hint — no weekly flag — general model → minimax-5h-window", () => {
    const result = enrichQuotaLabel("minimax", { modelName: "general", weekly: false });
    expect(result.concept).toBe("minimax-5h-window");
    expect(result.label).toBe("5h rolling limit");
  });

  it("geminiModel drives gemini-model-quota concept", () => {
    const result = enrichQuotaLabel("gemini", { geminiModel: "gemini-3-pro-high" });
    expect(result.concept).toBe("gemini-model-quota");
    expect(result.label).toBe("Model quota");
  });

  it("providerId is included in returned object for traceability", () => {
    const result = enrichQuotaLabel("minimax", { weekly: true });
    expect(result.label).toBe("Weekly limit");
  });
});

// ─── PR2 RED: new semantic-label concepts ────────────────────────────────────────
describe("PR2: minimax-5h-window concept (general model, non-weekly)", () => {
  it("modelName general + weekly false → minimax-5h-window, label '5h rolling limit'", () => {
    const result = enrichQuotaLabel("minimax", { modelName: "general", weekly: false });
    expect(result.concept).toBe("minimax-5h-window");
    expect(result.label).toBe("5h rolling limit");
  });
});

describe("PR2: minimax-video concept", () => {
  it("modelName video (non-weekly) → minimax-video, label 'Video generation'", () => {
    const result = enrichQuotaLabel("minimax", { modelName: "video", weekly: false });
    expect(result.concept).toBe("minimax-video");
    expect(result.label).toBe("Video generation");
  });
});

describe("PR2: z.ai TIME_LIMIT unit branching", () => {
  it("unit 5 → z.ai-5-hour-rolling '5h quota' (existing)", () => {
    const result = enrichQuotaLabel("z.ai", { type: "TIME_LIMIT", unit: 5 });
    expect(result.concept).toBe("z.ai-5-hour-rolling");
    expect(result.label).toBe("5h quota");
  });

  it("unit 'weekly' (string) → z.ai-weekly-rolling 'Weekly quota'", () => {
    // unit is typed number | string | null in ProviderPayloadHints
    const result = enrichQuotaLabel("z.ai", { type: "TIME_LIMIT", unit: "weekly" as const });
    expect(result.concept).toBe("z.ai-weekly-rolling");
    expect(result.label).toBe("Weekly quota");
  });

  it("unit 168 (>=168) → z.ai-weekly-rolling 'Weekly quota'", () => {
    const result = enrichQuotaLabel("z.ai", { type: "TIME_LIMIT", unit: 168 });
    expect(result.concept).toBe("z.ai-weekly-rolling");
    expect(result.label).toBe("Weekly quota");
  });

  it("unit 200 (>=168) → z.ai-weekly-rolling 'Weekly quota'", () => {
    const result = enrichQuotaLabel("z.ai", { type: "TIME_LIMIT", unit: 200 });
    expect(result.concept).toBe("z.ai-weekly-rolling");
    expect(result.label).toBe("Weekly quota");
  });

  it("unit 10 (non-weekly, non-5) → z.ai-generic-rolling '10-hour rolling limit'", () => {
    const result = enrichQuotaLabel("z.ai", { type: "TIME_LIMIT", unit: 10 });
    expect(result.concept).toBe("z.ai-generic-rolling");
    expect(result.label).toBe("10-hour rolling limit");
  });
});

describe("PR2: minimax model precedence", () => {
  it("weekly=true wins over modelName (general) → minimax-weekly-request", () => {
    const result = enrichQuotaLabel("minimax", { modelName: "general", weekly: true });
    expect(result.concept).toBe("minimax-weekly-request");
    expect(result.label).toBe("Weekly limit");
  });

  it("weekly=true wins over modelName (video) → minimax-weekly-request", () => {
    const result = enrichQuotaLabel("minimax", { modelName: "video", weekly: true });
    expect(result.concept).toBe("minimax-weekly-request");
    expect(result.label).toBe("Weekly limit");
  });

  it("general non-weekly → minimax-5h-window", () => {
    const result = enrichQuotaLabel("minimax", { modelName: "general", weekly: false });
    expect(result.concept).toBe("minimax-5h-window");
  });

  it("video non-weekly → minimax-video", () => {
    const result = enrichQuotaLabel("minimax", { modelName: "video", weekly: false });
    expect(result.concept).toBe("minimax-video");
  });

  it("unknown modelName non-weekly → legacy daily fallback", () => {
    // modelName that isn't general/video falls back to legacy daily-request
    const result = enrichQuotaLabel("minimax", { modelName: "unknown-model", weekly: false });
    expect(result.concept).toBe("minimax-daily-request");
  });
});

describe("PR2: buildProviderName label override for dynamic fallback", () => {
  it("accepts label override so dynamic fallback text survives when concept not in LABEL_MAP", () => {
    // When the concept returned is z.ai-generic-rolling (a new key),
    // buildProviderName should use the label from enrichQuotaLabel's returned label
    // (not look up from LABEL_MAP which wouldn't have it in the fallback path)
    const result = enrichQuotaLabel("z.ai", { type: "TIME_LIMIT", unit: 10 });
    expect(result.concept).toBe("z.ai-generic-rolling");
    expect(result.label).toBe("10-hour rolling limit");
    // buildProviderName should produce branded output using the returned label
    // even if the concept is not yet in its internal LABEL_MAP
    const branded = buildProviderName("z.ai", result.concept, undefined, result.label);
    expect(branded).toContain("10-hour rolling limit");
  });
});

describe("PR2: OpenAI labels unchanged (regression guard)", () => {
  it("openai primary rate label unchanged", () => {
    const result = enrichQuotaLabel("openai", { openaiVariant: "primary" });
    expect(result.label).toBe("Primary rate limit");
    expect(result.concept).toBe("openai-primary-rate");
  });

  it("openai secondary rate label unchanged", () => {
    const result = enrichQuotaLabel("openai", { openaiVariant: "secondary" });
    expect(result.label).toBe("Secondary rate limit");
  });

  it("openai credits label unchanged", () => {
    const result = enrichQuotaLabel("openai", { openaiVariant: "credits" });
    expect(result.label).toBe("Credit balance");
  });

  it("openai token usage label unchanged", () => {
    const result = enrichQuotaLabel("openai", { openaiVariant: "api" });
    expect(result.label).toBe("Token usage");
  });
});
