// RED: Footer hook — guard conditions + append behavior.
import { describe, it, expect } from "vitest";

const SIGNATURE = "<!-- quota-footer -->";
const STUB_FOOTER = "```text\nprovider: test, used: 5/10, reset: 12:00\n```";

async function makeDeps(overrides: Partial<{ renderFooter: () => Promise<string>; signature: string; show?: boolean }> = {}) {
  const { PluginState } = await import("../../../src/plugin/state.js");
  return {
    pluginState: new PluginState(() => 0),
    renderFooter: overrides.renderFooter ?? (async () => STUB_FOOTER),
    signature: overrides.signature ?? SIGNATURE,
    show: overrides.show,
  };
}

async function callHook(
  input: { sessionID: string; messageID: string; partID: string },
  output: { text: string },
  deps: Awaited<ReturnType<typeof makeDeps>>,
) {
  const { handleTextComplete } = await import("../../../src/plugin/footer-hook.js");
  return handleTextComplete(input, output, deps);
}

describe("handleTextComplete — appends footer when clean", () => {
  it.each([
    { text: "",                         description: "empty text"      },
    { text: "Here is my answer.\n",     description: "existing text"   },
    { text: "Some response",            description: "ends with text"   },
  ])("appends footer to $description", async ({ text }) => {
    const deps = await makeDeps();
    const output = { text };
    await callHook({ sessionID: "s1", messageID: "m1", partID: "p1" }, output, deps);
    expect(output.text).toContain(STUB_FOOTER);
  });
});

describe("handleTextComplete — skips guards", () => {
  it("skips when isProcessed(messageID)", async () => {
    const deps = await makeDeps();
    deps.pluginState.markProcessed("m1");
    const output = { text: "Hello" };
    await callHook({ sessionID: "s1", messageID: "m1", partID: "p1" }, output, deps);
    expect(output.text).toBe("Hello");
  });

  it("skips when isPending(messageID)", async () => {
    const deps = await makeDeps();
    deps.pluginState.markPending("m1");
    const output = { text: "Hello" };
    await callHook({ sessionID: "s1", messageID: "m1", partID: "p1" }, output, deps);
    expect(output.text).toBe("Hello");
  });

  it("skips and marks processed when signature already in text", async () => {
    const deps = await makeDeps();
    const original = "Hello\n" + SIGNATURE + "\n";
    const output = { text: original };
    await callHook({ sessionID: "s1", messageID: "m1", partID: "p1" }, output, deps);
    expect(output.text).toBe(original);
    expect(deps.pluginState.isProcessed("m1")).toBe(true);
  });
});

describe("handleTextComplete — second call skips (isProcessed)", () => {
  it("second call with same messageID skips after first completes", async () => {
    const deps = await makeDeps();
    let renderCount = 0;
    deps.renderFooter = async () => { renderCount++; return STUB_FOOTER; };
    const out1 = { text: "First" };
    await callHook({ sessionID: "s1", messageID: "m2", partID: "p1" }, out1, deps);
    expect(renderCount).toBe(1);
    const out2 = { text: "Second" };
    await callHook({ sessionID: "s1", messageID: "m2", partID: "p2" }, out2, deps);
    expect(renderCount).toBe(1); // not incremented
    expect(out2.text).toBe("Second");
  });
});

describe("handleTextComplete — fenced text block format", () => {
  it("footer is a fenced text block", async () => {
    const deps = await makeDeps();
    deps.renderFooter = async () => "```text\nfoo: bar\n```";
    const output = { text: "response" };
    await callHook({ sessionID: "s1", messageID: "m1", partID: "p1" }, output, deps);
    expect(output.text).toMatch(/```text\n[\s\S]+```$/);
  });
});

describe("handleTextComplete — show=false suppresses footer", () => {
  it("show=false appends nothing", async () => {
    const deps = await makeDeps({ show: false });
    const output = { text: "response" };
    await callHook({ sessionID: "s1", messageID: "m1", partID: "p1" }, output, deps);
    expect(output.text).toBe("response"); // no footer appended
  });

  it("show=false does not call renderFooter", async () => {
    let called = false;
    const deps = await makeDeps({ show: false, renderFooter: async () => { called = true; return STUB_FOOTER; } });
    const output = { text: "response" };
    await callHook({ sessionID: "s1", messageID: "m1", partID: "p1" }, output, deps);
    expect(called).toBe(false);
  });

  it("show=false marks message as processed (idempotent)", async () => {
    const deps = await makeDeps({ show: false });
    const output = { text: "response" };
    await callHook({ sessionID: "s1", messageID: "m1", partID: "p1" }, output, deps);
    expect(deps.pluginState.isProcessed("m1")).toBe(true);
  });
});

describe("handleTextComplete — show=true renders footer", () => {
  it("show=true appends footer", async () => {
    const deps = await makeDeps({ show: true });
    const output = { text: "response" };
    await callHook({ sessionID: "s1", messageID: "m1", partID: "p1" }, output, deps);
    expect(output.text).toContain(STUB_FOOTER);
  });

  it("show=undefined (omitted) defaults to true and renders footer", async () => {
    // show is optional — omitting it should behave like show:true
    const deps = await makeDeps(); // no show override
    const output = { text: "response" };
    await callHook({ sessionID: "s1", messageID: "m1", partID: "p1" }, output, deps);
    expect(output.text).toContain(STUB_FOOTER);
  });
});

describe("handleTextComplete — footer is idempotent", () => {
  it("second call with same messageID does not double-render", async () => {
    const deps = await makeDeps();
    let renderCount = 0;
    deps.renderFooter = async () => { renderCount++; return STUB_FOOTER; };
    const out1 = { text: "First" };
    await callHook({ sessionID: "s1", messageID: "m2", partID: "p1" }, out1, deps);
    const out2 = { text: "Second" };
    await callHook({ sessionID: "s1", messageID: "m2", partID: "p2" }, out2, deps);
    expect(renderCount).toBe(1);
    expect(out2.text).toBe("Second"); // no double-append
  });
});
