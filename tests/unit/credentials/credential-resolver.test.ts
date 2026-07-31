// RED → GREEN: credential resolution + redaction.
import { describe, it, expect, vi, beforeEach } from "vitest";
import authJsonFIXTURE from "../../fixtures/credentials/auth.json";
import { redact } from "../../../legacy/adapters/auth/redactor.js";

const mockFsRead = vi.fn();
vi.mock("node:fs", () => ({ readFileSync: mockFsRead }));

const XDG_AUTH_JSON = JSON.stringify(authJsonFIXTURE);
const loadFactory = () => import("../../../legacy/adapters/auth/credential-resolver.js");
const emptyConfig = { displayMode: "table" as const, disabled: [] as string[], aggregatedGroups: {}, historyMaxAgeHours: 24, pollingInterval: 0, predictionWindowMinutes: 60, predictionShortWindowMinutes: 5, showUnaggregated: false };
function fs(r: (p: string) => string) { return { readFileSync: r } as unknown as { readFileSync: (p: string) => string }; }

describe("credential-resolver", () => {
  beforeEach(() => { vi.resetModules(); vi.resetAllMocks(); mockFsRead.mockImplementation((p) => { if (String(p).includes("xdg")) return XDG_AUTH_JSON; if (String(p).includes(".local/share")) return XDG_AUTH_JSON; const e = new Error("ENOENT") as Error & { code: string }; e.code = "ENOENT"; throw e; }); });

  it.each([
    { p: "openai", v: "oauth", k: "ya29.a0AfH6SMBx" },
    { p: "opencode-zen", v: "api", k: "sk-opencode-zen-test-key-1234567890abcdef" },
    { p: "anthropic", v: "api", k: "sk-ant-test-key-abcdefghijklmnop" },
    { p: "google-gemini", v: "wellknown", k: "AIzaSyD" },
    { p: "minimax-coding-plan", v: "oauth" }, { p: "kimi-for-coding", v: "oauth" }, { p: "zai-coding-plan", v: "oauth" },
  ])("resolves $p as $v from auth.json", async ({ p, v, k }) => {
    const { createCredentialResolver } = await loadFactory();
    const r = createCredentialResolver(emptyConfig, fs(mockFsRead as unknown as (p: string) => string), { XDG_DATA_HOME: "/xdg/data" });
    const c = await r.get(p);
    expect(c).not.toBeNull(); expect(c!.variant).toBe(v);
    if (k) expect((c as { key?: string }).key ?? (c as { access?: string }).access).toBe(k);
  });

  it("falls back to ANTHROPIC_API_KEY when no auth.json entry", async () => {
    mockFsRead.mockReturnValue("{}");
    const { createCredentialResolver } = await loadFactory();
    const r = createCredentialResolver(emptyConfig, fs(mockFsRead as unknown as (p: string) => string), { ANTHROPIC_API_KEY: "sk-ant-env", XDG_DATA_HOME: "/xdg/data" });
    const c = await r.get("anthropic");
    expect(c?.variant).toBe("api"); expect((c as { key: string }).key).toBe("sk-ant-env");
  });

  it("prefers auth.json over env", async () => {
    const { createCredentialResolver } = await loadFactory();
    const r = createCredentialResolver(emptyConfig, fs(mockFsRead as unknown as (p: string) => string), { ANTHROPIC_API_KEY: "sk-ignored", XDG_DATA_HOME: "/xdg/data" });
    expect((await r.get("anthropic") as { key: string }).key).toBe("sk-ant-test-key-abcdefghijklmnop");
  });

  it("uses XDG_DATA_HOME path when set", async () => {
    const { createCredentialResolver } = await loadFactory();
    expect(await createCredentialResolver(emptyConfig, fs(mockFsRead as unknown as (p: string) => string), { XDG_DATA_HOME: "/xdg/data" }).get("openai")).not.toBeNull();
  });

  it("falls back to ~/.local/share when XDG unset", async () => {
    mockFsRead.mockImplementation((p) => { if (String(p).includes(".local/share")) return XDG_AUTH_JSON; const e = new Error("ENOENT") as Error & { code: string }; e.code = "ENOENT"; throw e; });
    const { createCredentialResolver } = await loadFactory();
    expect(await createCredentialResolver(emptyConfig, fs(mockFsRead as unknown as (p: string) => string), {}).get("openai")).not.toBeNull();
  });

  it("returns null when no source has credential", async () => {
    mockFsRead.mockImplementation(() => { const e = new Error("ENOENT") as Error & { code: string }; e.code = "ENOENT"; throw e; });
    const { createCredentialResolver } = await loadFactory();
    expect(await createCredentialResolver(emptyConfig, fs(mockFsRead as unknown as (p: string) => string), {}).get("openai")).toBeNull();
  });

  it("returns null for unknown provider", async () => {
    const { createCredentialResolver } = await loadFactory();
    expect(await createCredentialResolver(emptyConfig, fs(mockFsRead as unknown as (p: string) => string), { XDG_DATA_HOME: "/xdg/data" }).get("nonexistent")).toBeNull();
  });

  it("skips malformed entry and falls through to env", async () => {
    mockFsRead.mockReturnValue(JSON.stringify({ openai: { type: "unknown" } }));
    const { createCredentialResolver } = await loadFactory();
    const r = createCredentialResolver(emptyConfig, fs(mockFsRead as unknown as (p: string) => string), { OPENAI_API_KEY: "sk-env-test", XDG_DATA_HOME: "/xdg/data" });
    expect((await r.get("openai"))?.variant).toBe("api");
  });

  it("ignores extra unknown fields in oauth", async () => {
    mockFsRead.mockReturnValue(JSON.stringify({ openai: { type: "oauth", access: "acc", refresh: "ref", expires: 0, extra: "ignored" } }));
    const { createCredentialResolver } = await loadFactory();
    expect((await createCredentialResolver(emptyConfig, fs(mockFsRead as unknown as (p: string) => string), { XDG_DATA_HOME: "/xdg/data" }).get("openai"))?.variant).toBe("oauth");
  });
});

describe("redactor", () => {
  it.each([
    { k: "key", v: "sk-abcdefghijklmnop", m: "sk-a****" },
    { k: "key", v: "key_abcdefgh", m: "key****" },
    { k: "access", v: "acc_abc", m: "acc****" },
    { k: "refresh", v: "ref_xyz", m: "ref****" },
    { k: "token", v: "tok_short", m: "tok****" },
    { k: "apiKey", v: "key_abcdefgh", m: "key****" },
    { k: "password", v: "supersecret", m: "sup****" },
    { k: "secret", v: "mysecretvalue", m: "mys****" },
  ])("redacts $k", ({ k, v, m }) => expect(redact({ [k]: v })).toMatchObject({ [k]: m }));

  it("redacts nested", () => { const r = redact({ outer: { inner: { key: "deep_key_value" } } }) as Record<string, unknown>; expect(((r.outer as Record<string, unknown>).inner as Record<string, unknown>).key).toBe("dee****"); });
  it("preserves safe fields", () => expect(redact({ name: "openai", region: "us-east" })).toMatchObject({ name: "openai", region: "us-east" }));
  it("preserves numbers", () => expect(redact({ expires: 1761523200 })).toMatchObject({ expires: 1761523200 }));
  it("handles null", () => expect(redact(null)).toBeNull());
  it("handles arrays", () => expect(redact([{ key: "k1" }, { key: "k2" }])).toMatchObject([{ key: "k1****" }, { key: "k2****" }]));
});
