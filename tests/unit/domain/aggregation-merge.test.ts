// RED: mergeAggregationGroups — user config wins on id collision.
import { describe, it, expect } from "vitest";
import { mergeAggregationGroups } from "../../../legacy/domain/aggregation.js";
import type { AggregationGroup } from "../../../legacy/domain/aggregation.js";

// ── helpers ────────────────────────────────────────────────────────────────────

const def = (id: string, providerId = "zen", strategy: AggregationGroup["strategy"] = "most_critical"): AggregationGroup =>
  Object.freeze({ id, providerId, strategy });

const user = (id: string, providerId = "zen", strategy: AggregationGroup["strategy"] = "most_critical"): AggregationGroup =>
  Object.freeze({ id, providerId, strategy });

// 5 defaults (from aggregation-defaults)
const FIVE_DEFAULTS: readonly AggregationGroup[] = Object.freeze([
  def("opencode-zen-monthly", "zen", "most_critical"),
  def("opencode-go-monthly", "go", "most_critical"),
  def("zai-coding-plan-weekly", "zai", "most_critical"),
  def("kimi-daily", "kimi", "most_critical"),
  def("minimax-monthly", "minimax", "most_critical"),
]);

describe("mergeAggregationGroups", () => {
  describe("empty user config returns defaults", () => {
    it("empty user → all 5 defaults returned", () => {
      const result = mergeAggregationGroups([], FIVE_DEFAULTS);
      expect(result).toHaveLength(5);
    });

    it("empty user → same default references returned (deep equal)", () => {
      const result = mergeAggregationGroups([], FIVE_DEFAULTS);
      expect(result).toStrictEqual(FIVE_DEFAULTS);
    });
  });

  describe("user group with new id adds to defaults", () => {
    it("user adds G → 6 total", () => {
      const userGroup = user("custom-group", "custom", "max");
      const result = mergeAggregationGroups([userGroup], FIVE_DEFAULTS);
      expect(result).toHaveLength(6);
    });

    it("new group appears in result", () => {
      const userGroup = user("custom-group", "custom", "max");
      const result = mergeAggregationGroups([userGroup], FIVE_DEFAULTS);
      expect(result.find((g) => g.id === "custom-group")).toBe(userGroup);
    });

    it("original defaults still present", () => {
      const userGroup = user("custom-group", "custom", "max");
      const result = mergeAggregationGroups([userGroup], FIVE_DEFAULTS);
      for (const d of FIVE_DEFAULTS) {
        expect(result.find((g) => g.id === d.id)).toBe(d);
      }
    });
  });

  describe("user group with same id replaces default", () => {
    it("user G with id 'opencode-zen-monthly' replaces default", () => {
      const override = user("opencode-zen-monthly", "zen", "max");
      const result = mergeAggregationGroups([override], FIVE_DEFAULTS);
      const found = result.find((g) => g.id === "opencode-zen-monthly");
      expect(found).toBe(override);
      expect(found?.strategy).toBe("max"); // user wins
    });

    it("default G is absent when user overrides", () => {
      const override = user("opencode-zen-monthly", "zen", "max");
      const result = mergeAggregationGroups([override], FIVE_DEFAULTS);
      const count = result.filter((g) => g.id === "opencode-zen-monthly");
      expect(count).toHaveLength(1);
    });

    it("other defaults still present", () => {
      const override = user("opencode-zen-monthly", "zen", "max");
      const result = mergeAggregationGroups([override], FIVE_DEFAULTS);
      expect(result).toHaveLength(5);
    });
  });

  describe("user config with multiple groups", () => {
    it("user adds 2 groups → 7 total", () => {
      const g1 = user("custom-1", "c1", "min");
      const g2 = user("custom-2", "c2", "median");
      const result = mergeAggregationGroups([g1, g2], FIVE_DEFAULTS);
      expect(result).toHaveLength(7);
    });

    it("user overrides 1 of 5 and adds 1 new → 6 total", () => {
      const override = user("opencode-go-monthly", "go", "min");
      const newOne = user("extra", "extra", "max");
      const result = mergeAggregationGroups([override, newOne], FIVE_DEFAULTS);
      expect(result).toHaveLength(6);
    });
  });

  describe("merge result is readonly", () => {
    it("returned array is frozen", () => {
      const result = mergeAggregationGroups([], FIVE_DEFAULTS);
      expect(Object.isFrozen(result)).toBe(true);
    });

    it("returned array elements are frozen", () => {
      const g = user("custom", "c", "max");
      const result = mergeAggregationGroups([g], FIVE_DEFAULTS);
      for (const elem of result) {
        expect(Object.isFrozen(elem)).toBe(true);
      }
    });
  });
});
