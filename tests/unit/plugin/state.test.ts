// RED: PluginState + SimpleLock — set/get/lock semantics with injectable clock.
import { describe, it, expect, vi } from "vitest";

describe("SimpleLock", () => {
  it("acquire returns a release function", async () => {
    const { SimpleLock } = await import("../../../src/plugin/state.js");
    const lock = new SimpleLock(() => 0);
    const release = await lock.acquire("msg1");
    expect(typeof release).toBe("function");
    release();
  });

  it("same key blocks until released", async () => {
    const { SimpleLock } = await import("../../../src/plugin/state.js");
    const lock = new SimpleLock(() => 0);
    const release1 = await lock.acquire("msg1");

    let unblocked = false;
    const p = lock.acquire("msg1").then(() => { unblocked = true; });
    // Not yet unblocked while first lock is held
    expect(unblocked).toBe(false);

    release1();
    await p;
    expect(unblocked).toBe(true);
  });

  it("different keys do not block each other", async () => {
    const { SimpleLock } = await import("../../../src/plugin/state.js");
    const lock = new SimpleLock(() => 0);
    const release1 = await lock.acquire("msg1");
    const release2 = await lock.acquire("msg2");
    expect(typeof release2).toBe("function");
    release1();
    release2();
  });
});

describe("PluginState", () => {
  it("isProcessed returns false for unseen message", async () => {
    const { PluginState } = await import("../../../src/plugin/state.js");
    const state = new PluginState(() => 0);
    expect(state.isProcessed("unknown")).toBe(false);
  });

  it("markProcessed makes isProcessed return true", async () => {
    const { PluginState } = await import("../../../src/plugin/state.js");
    const state = new PluginState(() => 0);
    state.markProcessed("msg1");
    expect(state.isProcessed("msg1")).toBe(true);
  });

  it("isPending returns false for unseen message", async () => {
    const { PluginState } = await import("../../../src/plugin/state.js");
    const state = new PluginState(() => 0);
    expect(state.isPending("unknown")).toBe(false);
  });

  it("markPending makes isPending return true", async () => {
    const { PluginState } = await import("../../../src/plugin/state.js");
    const state = new PluginState(() => 0);
    state.markPending("msg1");
    expect(state.isPending("msg1")).toBe(true);
  });

  it("acquireLock returns release function", async () => {
    const { PluginState } = await import("../../../src/plugin/state.js");
    const state = new PluginState(() => 0);
    const release = await state.acquireLock("msg1");
    expect(typeof release).toBe("function");
    release();
  });

  it("isPending becomes true after markPending", async () => {
    const { PluginState } = await import("../../../src/plugin/state.js");
    const state = new PluginState(() => 0);
    state.markPending("msg1");
    expect(state.isPending("msg1")).toBe(true);
  });

  it("isPending becomes false after markPending then delete", async () => {
    const { PluginState } = await import("../../../src/plugin/state.js");
    const state = new PluginState(() => 0);
    state.markPending("msg1");
    expect(state.isPending("msg1")).toBe(true);
    state.pendingSet.delete("msg1"); // simulate lock release clearing pending
    expect(state.isPending("msg1")).toBe(false);
  });

  it("two concurrent acquires of same messageID — only first holds lock", async () => {
    const { PluginState } = await import("../../../src/plugin/state.js");
    const state = new PluginState(() => 0);

    const release1 = await state.acquireLock("msg1");
    expect(state.isPending("msg1")).toBe(false); // acquireLock does NOT set isPending

    // Second acquire waits while first holds the lock
    let secondAcquired = false;
    const p = state.acquireLock("msg1").then(() => {
      secondAcquired = true;
    });

    // Second is still waiting
    expect(secondAcquired).toBe(false);

    // Release first — second can now proceed
    release1();
    await p;
    expect(secondAcquired).toBe(true);
  });
});
