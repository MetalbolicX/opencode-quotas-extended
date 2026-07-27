// RED: parseUsage + windowMap — window normalization and info population.
// These tests define the shared contract for the 5 coding-plan providers.
import { describe, it, expect } from "vitest";
import { parseUsage, windowMap } from "../../../src/adapters/providers/coding-plan-parse.js";

describe("windowMap", () => {
  const cases: [string, "daily" | "monthly" | "rolling"][] = [
    ["Daily", "daily"],
    ["daily", "daily"],
    ["DAILY", "daily"],
    ["Monthly", "monthly"],
    ["monthly", "monthly"],
    ["Monthly Reset", "monthly"],
    ["Month", "monthly"],
    ["Weekly", "rolling"],
    ["weekly", "rolling"],
    ["week", "rolling"],
    ["5h window", "rolling"],
    ["hourly", "rolling"],
    ["12h limit", "rolling"],
    ["unknown", "rolling"],
    ["", "rolling"],
    [undefined as unknown as string, "rolling"],
  ];

  it.each(cases)("windowMap(%j) → %s", (label, expected) => {
    expect(windowMap(label as string | undefined)).toBe(expected);
  });
});

describe("parseUsage", () => {
  it("consumes windows + credits → entries with window normalized and info populated", () => {
    const input = {
      windows: [
        { label: "Daily", used: 40, limit: 100 },
        { label: "Monthly", used: 320, limit: 1000 },
      ],
      credits: { balance: 12.5, unlimited: false },
    };
    const result = parseUsage(input, "zai", "z.ai");
    expect(result).toHaveLength(3); // 2 windows + 1 credits
    const daily = result.find((q) => q.id === "zai-daily")!;
    expect(daily).toMatchObject({
      used: 40, limit: 100, unit: "%", window: "daily",
    });
    expect(daily.info).toBe("z.ai Daily");
    const credits = result.find((q) => q.id === "zai-credits")!;
    expect(credits).toMatchObject({ used: 12.5, limit: null, unit: "credits", window: "rolling" });
    expect(credits.info).toBe("z.ai Credits");
  });

  it("skips malformed window (non-numeric used) without throwing", () => {
    const input = {
      windows: [
        { label: "Daily", used: "not-a-number", limit: 100 },
        { label: "Monthly", used: 50, limit: 200 },
      ],
    };
    const result = parseUsage(input, "kimi", "Kimi");
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe("kimi-monthly");
    expect(result[0].used).toBe(50);
  });

  it("skips window when used is null or undefined", () => {
    const input = {
      windows: [
        { label: "Daily", used: null, limit: 100 },
        { label: "Hourly", used: undefined, limit: 50 },
        { label: "Weekly", used: 25, limit: 80 },
      ],
    };
    const result = parseUsage(input, "test", "Test");
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe("test-weekly");
  });

  it("uses windowMap to normalize window field", () => {
    const input = {
      windows: [
        { label: "Daily", used: 10, limit: 100 },
        { label: "Monthly", used: 20, limit: 200 },
        { label: "5h window", used: 30, limit: 300 },
      ],
    };
    const result = parseUsage(input, "zen", "Zen");
    expect(result.find((q) => q.id === "zen-daily")?.window).toBe("daily");
    expect(result.find((q) => q.id === "zen-monthly")?.window).toBe("monthly");
    expect(result.find((q) => q.id === "zen-5h window")?.window).toBe("rolling");
  });

  it("populates info field on every entry", () => {
    const input = { windows: [{ label: "Daily", used: 5, limit: 50 }] };
    const result = parseUsage(input, "minimax", "Minimax");
    expect(result[0].info).toBe("Minimax Daily");
  });

  it("returns empty array when input is null or not an object", () => {
    expect(parseUsage(null, "x", "X")).toEqual([]);
    expect(parseUsage("string", "x", "X")).toEqual([]);
    expect(parseUsage([], "x", "X")).toEqual([]);
  });

  it("returns empty array when windows is absent", () => {
    expect(parseUsage({}, "x", "X")).toEqual([]);
  });

  it("omits credits entry when unlimited is true", () => {
    const input = { windows: [], credits: { balance: 999, unlimited: true } };
    expect(parseUsage(input, "go", "Go")).toEqual([]);
  });

  it("omits credits entry when balance is non-numeric", () => {
    const input = { windows: [], credits: { balance: "unknown", unlimited: false } };
    expect(parseUsage(input, "go", "Go")).toEqual([]);
  });

  it("id prefix is used in entry ids", () => {
    const input = { windows: [{ label: "Daily", used: 1, limit: 10 }] };
    const result = parseUsage(input, "my-prefix", "MyProvider");
    expect(result[0].id).toBe("my-prefix-daily");
  });
});

// ── parseZaiLimits: z.ai envelope { data: { limits: [...] } } ──────────────
import { parseZaiLimits } from "../../../src/adapters/providers/coding-plan-parse.js";

describe("parseZaiLimits", () => {
  const timeLimitEntry = {
    type: "TIME_LIMIT",
    unit: 5,
    number: 1,
    usage: 100,
    currentValue: 0,
    remaining: 100,
    percentage: 0,
    nextResetTime: 1750000000000,
    usageDetails: [],
  };

  it("parses a real z.ai envelope with one TIME_LIMIT entry", () => {
    const input = {
      code: 200,
      msg: "success",
      data: { limits: [timeLimitEntry] },
    };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result).toHaveLength(1);
    expect(result[0].used).toBe(0);
    expect(result[0].limit).toBe(100);
    expect(result[0].unit).toBe("%");
    expect(result[0].reset).toBeInstanceOf(Date);
    expect(result[0].id).toContain("time_limit");
  });

  it("returns [] when data is missing", () => {
    expect(parseZaiLimits({}, "zai", "z.ai")).toEqual([]);
  });

  it("returns [] when data.limits is not an array", () => {
    expect(parseZaiLimits({ data: { limits: "nope" } }, "zai", "z.ai")).toEqual([]);
  });

  it("returns [] when data.limits is empty", () => {
    expect(parseZaiLimits({ data: { limits: [] } }, "zai", "z.ai")).toEqual([]);
  });

  it("parses multiple limits into multiple entries using percentage as source of truth", () => {
    const input = {
      data: {
        limits: [
          timeLimitEntry,
          { type: "TOKENS_LIMIT", unit: 1, number: 1, usage: 500000, currentValue: 12345, remaining: 487655, percentage: 2, nextResetTime: null, usageDetails: [] },
        ],
      },
    };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result).toHaveLength(2);
    expect(result[0].id).toContain("time_limit");
    expect(result[1].id).toContain("tokens_limit");
    // percentage is the source of truth → used = 2, limit = 100
    expect(result[1].used).toBe(2);
    expect(result[1].limit).toBe(100);
    expect(result[1].window).toBe("rolling-tokens");
  });

  it("handles missing nextResetTime by leaving reset: null", () => {
    const input = {
      data: { limits: [{ ...timeLimitEntry, nextResetTime: null }] },
    };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result[0].reset).toBeNull();
  });
});

describe("parseZaiLimits — percentage + window identity", () => {
  it("uses l.percentage as used and fixes limit=100 for a TIME_LIMIT 5h row", () => {
    const input = {
      code: 200, msg: "success",
      data: { limits: [{
        type: "TIME_LIMIT", unit: 5, number: 1,
        usage: 100, currentValue: 0, remaining: 100,
        percentage: 12, nextResetTime: 1750000000000, usageDetails: [],
      }] },
    };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result).toHaveLength(1);
    expect(result[0].used).toBe(12);
    expect(result[0].limit).toBe(100);
    expect(result[0].unit).toBe("%");
  });

  it("preserves a distinct window for the 5h TIME_LIMIT row", () => {
    const input = {
      data: { limits: [{
        type: "TIME_LIMIT", unit: 5, number: 1,
        usage: 100, currentValue: 0, percentage: 12,
        nextResetTime: 1750000000000, usageDetails: [],
      }] },
    };
    const result = parseZaiLimits(input, "zai", "z.ai");
    // window must NOT be the generic "rolling" — must reflect the 5h limit
    expect(result[0].window).not.toBe("rolling");
    // and the providerName must mention the 5h context
    expect(result[0].providerName.toLowerCase()).toContain("5");
  });

  it("emits a separate row for MCP_LIMIT with its own window", () => {
    const input = {
      data: { limits: [
        { type: "TIME_LIMIT", unit: 5, number: 1, usage: 100, currentValue: 0, percentage: 12, nextResetTime: 1750000000000, usageDetails: [] },
        { type: "MCP_LIMIT", unit: 1, number: 1, usage: 1000, currentValue: 200, percentage: 20, nextResetTime: 1750000000000, usageDetails: [] },
      ] },
    };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result).toHaveLength(2);
    expect(result[0].providerName).not.toBe(result[1].providerName);
    expect(result[1].used).toBe(20);
  });

  it("falls back to currentValue/usage*100 when percentage is missing", () => {
    const input = {
      data: { limits: [{
        type: "TIME_LIMIT", unit: 5, number: 1,
        usage: 100, currentValue: 25, remaining: 75,
        percentage: null, nextResetTime: 1750000000000, usageDetails: [],
      }] },
    };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result[0].used).toBeCloseTo(25, 1);
  });
});
