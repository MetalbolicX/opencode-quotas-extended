// RED: Five default coding-plan aggregation groups (most_critical strategy).
// Pure data — no I/O, no network.
import { describe, it, expect } from "vitest";
import { DEFAULT_AGGREGATION_GROUPS } from "../../../src/domain/aggregation-defaults.js";
import type { AggregationGroup } from "../../../src/domain/aggregation.js";

const VALID_PROVIDER_IDS: readonly string[] = ["zen", "go", "zai", "kimi", "minimax"];

describe("DEFAULT_AGGREGATION_GROUPS", () => {
  describe("exports 5 default groups", () => {
    it("array has length 5", () => {
      expect(DEFAULT_AGGREGATION_GROUPS).toHaveLength(5);
    });

    it("each group has id, providerId, and strategy fields", () => {
      for (const g of DEFAULT_AGGREGATION_GROUPS) {
        expect(g).toHaveProperty("id");
        expect(g).toHaveProperty("providerId");
        expect(g).toHaveProperty("strategy");
      }
    });

    it("each id is a non-empty string", () => {
      for (const g of DEFAULT_AGGREGATION_GROUPS) {
        expect(typeof g.id).toBe("string");
        expect(g.id.length).toBeGreaterThan(0);
      }
    });
  });

  describe("default groups are pure", () => {
    it("DEFAULT_AGGREGATION_GROUPS array is frozen", () => {
      expect(Object.isFrozen(DEFAULT_AGGREGATION_GROUPS)).toBe(true);
    });

    it("each group object is frozen", () => {
      for (const g of DEFAULT_AGGREGATION_GROUPS) {
        expect(Object.isFrozen(g)).toBe(true);
      }
    });
  });

  describe("id is unique per default group", () => {
    it("no duplicate ids", () => {
      const ids = DEFAULT_AGGREGATION_GROUPS.map((g) => g.id);
      const unique = new Set(ids);
      expect(unique.size).toBe(ids.length);
    });
  });

  describe("every default has a valid providerId", () => {
    it("all 5 providerIds are the coding-plan providers", () => {
      const providerIds = DEFAULT_AGGREGATION_GROUPS.map((g) => g.providerId);
      expect(providerIds).toEqual(VALID_PROVIDER_IDS);
    });

    it("each providerId maps to a known coding-plan provider", () => {
      for (const g of DEFAULT_AGGREGATION_GROUPS) {
        expect(VALID_PROVIDER_IDS).toContain(g.providerId);
      }
    });
  });

  describe("every default uses most_critical strategy", () => {
    it("all groups use most_critical", () => {
      for (const g of DEFAULT_AGGREGATION_GROUPS) {
        expect(g.strategy).toBe("most_critical");
      }
    });
  });

  describe("group ids match expected naming pattern", () => {
    it("expected ids are present", () => {
      const ids = DEFAULT_AGGREGATION_GROUPS.map((g) => g.id).sort();
      const expected = [
        "opencode-go-monthly",
        "opencode-zen-monthly",
        "zai-coding-plan-weekly",
        "kimi-daily",
        "minimax-monthly",
      ].sort();
      expect(ids).toEqual(expected);
    });
  });
});
