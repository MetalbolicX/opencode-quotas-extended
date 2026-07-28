// RED: semantic-label helpers — pure unit tests for enrichQuotaLabel + buildProviderName.
// WU-2: no raw type/tuple leakage; all 10 concepts covered; brand separator invariant.
import { describe, it, expect } from "vitest";
import { enrichQuotaLabel, buildProviderName } from "../../../src/rendering/semantic-labels.js";
import type { QuotaConcept } from "../../../src/rendering/semantic-labels.js";

describe("QuotaConcept exhaustive table", () => {
  const cases: Array<{ hints: Parameters<typeof enrichQuotaLabel>[1]; expectedConcept: QuotaConcept; expectedLabel: string }> = [
    // z.ai concepts
    { hints: { type: "TIME_LIMIT", unit: 5 }, expectedConcept: "z.ai-5-hour-rolling", expectedLabel: "5-hour rolling limit" },
    { hints: { type: "MCP_LIMIT", unit: 1 }, expectedConcept: "z.ai-mcp", expectedLabel: "MCP quota" },
    { hints: { type: "TOKENS_LIMIT", unit: 3 }, expectedConcept: "z.ai-token", expectedLabel: "Token quota" },
    // minimax concepts
    { hints: { modelName: "general", weekly: false }, expectedConcept: "minimax-daily-request", expectedLabel: "Daily request quota" },
    { hints: { modelName: "general", weekly: true }, expectedConcept: "minimax-weekly-request", expectedLabel: "Weekly request quota" },
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
    expect(result).toBe("z.ai\u00A0·\u00A05-hour rolling limit");
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
    expect(result.label).toBe("Weekly request quota");
  });

  it("daily minimax hint — no weekly flag — drives daily concept", () => {
    const result = enrichQuotaLabel("minimax", { modelName: "general", weekly: false });
    expect(result.concept).toBe("minimax-daily-request");
    expect(result.label).toBe("Daily request quota");
  });

  it("geminiModel drives gemini-model-quota concept", () => {
    const result = enrichQuotaLabel("gemini", { geminiModel: "gemini-3-pro-high" });
    expect(result.concept).toBe("gemini-model-quota");
    expect(result.label).toBe("Model quota");
  });

  it("providerId is included in returned object for traceability", () => {
    const result = enrichQuotaLabel("minimax", { weekly: true });
    expect(result.label).toBe("Weekly request quota");
  });
});
