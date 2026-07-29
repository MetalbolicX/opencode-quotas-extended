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

// ── PR4 RED tests: Z.Ai three-row ordering, unit branching, percentage, fallback ──────────────

/**
 * RED 4.1.1 — scrambled input.
 * parseZaiLimits MUST sort output as: rolling-mcp → rolling-5h → rolling-weekly.
 * Input order is [weekly, 5h, MCP]; expected output order must be sorted.
 */
describe("parseZaiLimits — PR4 row order (MCP → 5h → weekly)", () => {
  const weeklyEntry = {
    type: "TIME_LIMIT", unit: 168, number: 1,
    usage: 100, currentValue: 87, remaining: 13,
    percentage: 13, nextResetTime: 1750000000000, usageDetails: [],
  };
  const fiveHEntry = {
    type: "TIME_LIMIT", unit: 5, number: 1,
    usage: 100, currentValue: 88, remaining: 12,
    percentage: 12, nextResetTime: 1750000000000, usageDetails: [],
  };
  const mcpEntry = {
    type: "MCP_LIMIT", unit: 1, number: 1,
    usage: 1000, currentValue: 800, remaining: 200,
    percentage: 20, nextResetTime: 1750000000000, usageDetails: [],
  };

  it("sorts rows as MCP → 5h → weekly regardless of payload order", () => {
    // Scrambled: weekly first, then 5h, then MCP
    const input = { code: 200, msg: "success", data: { limits: [weeklyEntry, fiveHEntry, mcpEntry] } };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result).toHaveLength(3);
    // Must be sorted: rolling-mcp first, rolling-5h second, rolling-weekly third
    expect(result[0].window).toBe("rolling-mcp");
    expect(result[1].window).toBe("rolling-5h");
    expect(result[2].window).toBe("rolling-weekly");
  });

  it("wrong row count: only 2 rows → those 2 rows are still sorted correctly", () => {
    // When only 2 rows present, they should still be sorted: MCP first, 5h second (no weekly)
    const input = { code: 200, msg: "success", data: { limits: [weeklyEntry, fiveHEntry, mcpEntry].slice(1) } };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result).toHaveLength(2);
    expect(result[0].window).toBe("rolling-mcp");
    expect(result[1].window).toBe("rolling-5h");
  });

  it("4 rows (extra non-standard unit) → canonical 3 are sorted + 1 fallback", () => {
    const extraEntry = {
      type: "TIME_LIMIT", unit: 10, number: 1,
      usage: 100, currentValue: 90, remaining: 10,
      percentage: 10, nextResetTime: 1750000000000, usageDetails: [],
    };
    const input = { code: 200, msg: "success", data: { limits: [fiveHEntry, mcpEntry, weeklyEntry, extraEntry] } };
    const result = parseZaiLimits(input, "zai", "z.ai");
    // Expect 4: 3 canonical sorted + 1 non-standard fallback
    expect(result).toHaveLength(4);
    expect(result[0].window).toBe("rolling-mcp");
    expect(result[1].window).toBe("rolling-5h");
    expect(result[2].window).toBe("rolling-weekly");
    expect(result[3].window).toBe("rolling"); // unit=10 fallback
    expect(result[3].info).toMatch(/10-hour rolling limit/);
  });
});

/**
 * RED 4.1.2 — unit branching: 5h and weekly TIME_LIMIT must NOT collapse.
 */
describe("parseZaiLimits — PR4 unit branching (5h ≠ weekly)", () => {
  it("5h TIME_LIMIT and weekly TIME_LIMIT produce distinct info labels", () => {
    const input = {
      code: 200, msg: "success",
      data: { limits: [
        { type: "TIME_LIMIT", unit: 5, number: 1, usage: 100, currentValue: 88, remaining: 12, percentage: 12, nextResetTime: 1750000000000, usageDetails: [] },
        { type: "TIME_LIMIT", unit: 168, number: 1, usage: 100, currentValue: 87, remaining: 13, percentage: 13, nextResetTime: 1750000000000, usageDetails: [] },
      ] },
    };
    const result = parseZaiLimits(input, "zai", "z.ai");
    const fiveh = result.find(q => q.window === "rolling-5h");
    const weekly = result.find(q => q.window === "rolling-weekly");
    expect(fiveh).toBeDefined();
    expect(weekly).toBeDefined();
    expect(fiveh!.info).not.toBe(weekly!.info);
    expect(fiveh!.info.toLowerCase()).toContain("5");
    expect(weekly!.info.toLowerCase()).toContain("week");
  });

  it("unit=168 maps to rolling-weekly window (not rolling-168h)", () => {
    const input = {
      code: 200, msg: "success",
      data: { limits: [{
        type: "TIME_LIMIT", unit: 168, number: 1,
        usage: 100, currentValue: 87, remaining: 13,
        percentage: 13, nextResetTime: 1750000000000, usageDetails: [],
      }] },
    };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result[0].window).toBe("rolling-weekly");
  });
});

/**
 * RED 4.1.3 — weekly ~13% percentage must be preserved.
 */
describe("parseZaiLimits — PR4 weekly ~13% preserved", () => {
  it("weekly row used equals input percentage (~13)", () => {
    const input = {
      code: 200, msg: "success",
      data: { limits: [
        { type: "TIME_LIMIT", unit: 5, number: 1, usage: 100, currentValue: 88, remaining: 12, percentage: 12, nextResetTime: 1750000000000, usageDetails: [] },
        { type: "MCP_LIMIT", unit: 1, number: 1, usage: 1000, currentValue: 800, remaining: 200, percentage: 20, nextResetTime: 1750000000000, usageDetails: [] },
        { type: "TIME_LIMIT", unit: 168, number: 1, usage: 100, currentValue: 87, remaining: 13, percentage: 13, nextResetTime: 1750000000000, usageDetails: [] },
      ] },
    };
    const result = parseZaiLimits(input, "zai", "z.ai");
    const weekly = result.find(q => q.window === "rolling-weekly");
    expect(weekly).toBeDefined();
    expect(weekly!.used).toBe(13);
    expect(weekly!.limit).toBe(100);
  });
});

/**
 * RED 4.1.4 — non-standard unit fallback.
 */
describe("parseZaiLimits — PR4 non-standard unit fallback", () => {
  it("unit=10 falls back to generic label with unit in info", () => {
    const input = {
      code: 200, msg: "success",
      data: { limits: [{
        type: "TIME_LIMIT", unit: 10, number: 1,
        usage: 100, currentValue: 90, remaining: 10,
        percentage: 10, nextResetTime: 1750000000000, usageDetails: [],
      }] },
    };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result).toHaveLength(1);
    // Must use generic fallback, NOT rolling-10h window
    expect(result[0].window).toBe("rolling");
    expect(result[0].info).toMatch(/10-hour rolling limit/);
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
    // MCP_LIMIT (used=20) sorts before TIME_LIMIT 5h (used=12) per new ZAI_WINDOW_ORDER
    expect(result[0].used).toBe(20);
    expect(result[1].used).toBe(12);
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

// ── Lite plan: MCP / 5h / weekly are encoded on different type+unit combinations ──
describe("parseZaiLimits — lite plan (level: 'lite')", () => {
  const liteEntry = {
    type: "TIME_LIMIT", unit: 5, number: 1,
    usage: 100, currentValue: 0, remaining: 100,
    percentage: 0, nextResetTime: 1787882656000, usageDetails: [],
  };
  const liteTokens5h = {
    type: "TOKENS_LIMIT", unit: 3, number: 5,
    percentage: 9, nextResetTime: 1785302459000,
  };
  const liteTokensWeekly = {
    type: "TOKENS_LIMIT", unit: 6, number: 1,
    percentage: 2, nextResetTime: 1785809056000,
  };

  it("TIME_LIMIT unit=5 → 'MCP quota'", () => {
    const input = { data: { level: "lite", limits: [liteEntry] } };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result[0].info).toBe("MCP quota");
    expect(result[0].window).toBe("rolling-mcp");
  });

  it("TOKENS_LIMIT unit=3 → '5h rolling window'", () => {
    const input = { data: { level: "lite", limits: [liteTokens5h] } };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result[0].info).toBe("5h rolling window");
    expect(result[0].window).toBe("rolling-5h");
  });

  it("TOKENS_LIMIT unit=6 → 'Weekly quota'", () => {
    const input = { data: { level: "lite", limits: [liteTokensWeekly] } };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result[0].info).toBe("Weekly quota");
    expect(result[0].window).toBe("rolling-weekly");
  });

  it("sorts lite plan rows as MCP → 5h → weekly", () => {
    const input = {
      data: {
        level: "lite",
        limits: [liteTokensWeekly, liteTokens5h, liteEntry],
      },
    };
    const result = parseZaiLimits(input, "zai", "z.ai");
    expect(result).toHaveLength(3);
    expect(result[0].window).toBe("rolling-mcp");
    expect(result[1].window).toBe("rolling-5h");
    expect(result[2].window).toBe("rolling-weekly");
  });
});
