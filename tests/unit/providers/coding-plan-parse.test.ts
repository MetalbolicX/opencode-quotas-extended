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
