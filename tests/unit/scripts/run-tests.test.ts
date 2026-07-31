// WU-3 tests — strict TDD RED first.
import { describe, it, expect, afterAll } from "vitest";
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const PROJECT_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const RUN_TESTS = join(PROJECT_ROOT, "scripts", "run-tests.mjs");

function stub(code) {
  return "console.log('STUB:" + code + "');process.exit(" + code + ");\n";
}
function stubHanging() {
  return "await new Promise(function(){});\n";
}

function mkFixture(files) {
  const dir =
    PROJECT_ROOT + "/tmp-test-fixtures/f-" + Date.now() + "-" + Math.random().toString(36).slice(2);
  mkdirSync(dir + "/lib/es6/src", { recursive: true });
  for (const { p, c } of files) {
    const fp = dir + "/lib/es6/src/" + p;
    mkdirSync(fp.split("/").slice(0, -1).join("/"), { recursive: true });
    writeFileSync(fp, c, "utf8");
  }
  return dir;
}

function cleanFixtures() {
  rmSync(PROJECT_ROOT + "/tmp-test-fixtures", { recursive: true, force: true });
}

function run(...args) {
  return new Promise((res) => {
    const p = spawn("node", [RUN_TESTS, ...args], { cwd: PROJECT_ROOT });
    p.on("close", (code) => res({ code }));
    p.on("error", () => res({ code: null }));
  });
}

describe("run-tests.mjs", () => {
  const EMPTY_FIX = mkFixture([]);

  afterAll(cleanFixtures);

  describe("--help", () => {
    it("exits 0", async () => {
      const { code } = await run("--help");
      expect(code).toBe(0);
    });
  });

  describe("REQ-TEST-1 glob", () => {
    it("*Tests.res.mjs found", async () => {
      const d = mkFixture([{ p: "d/ATests.res.mjs", c: stub(0) }]);
      try {
        expect((await run("--dir", d)).code).toBe(0);
      } finally {
        cleanFixtures();
      }
    });
    it("*.test.res.mjs found", async () => {
      const d = mkFixture([{ p: "d/A.test.res.mjs", c: stub(0) }]);
      try {
        expect((await run("--dir", d)).code).toBe(0);
      } finally {
        cleanFixtures();
      }
    });
    it("both suffixes together", async () => {
      const d = mkFixture([
        { p: "d/ATests.res.mjs", c: stub(0) },
        { p: "d/B.test.res.mjs", c: stub(0) },
      ]);
      try {
        expect((await run("--dir", d)).code).toBe(0);
      } finally {
        cleanFixtures();
      }
    });
    it("no files → non-zero", async () => {
      expect((await run("--dir", EMPTY_FIX)).code).not.toBe(0);
    });
  });

  describe("REQ-TEST-2/3 child exits", () => {
    it("all pass → 0", async () => {
      const d = mkFixture([
        { p: "a.test.res.mjs", c: stub(0) },
        { p: "b.test.res.mjs", c: stub(0) },
      ]);
      try {
        expect((await run("--dir", d)).code).toBe(0);
      } finally {
        cleanFixtures();
      }
    });
    it("one fail → non-zero", async () => {
      const d = mkFixture([{ p: "a.test.res.mjs", c: stub(0) }, { p: "b.test.res.mjs", c: stub(1) }]);
      try {
        expect((await run("--dir", d)).code).not.toBe(0);
      } finally {
        cleanFixtures();
      }
    });
    it("all fail → non-zero", async () => {
      const d = mkFixture([{ p: "a.test.res.mjs", c: stub(2) }, { p: "b.test.res.mjs", c: stub(3) }]);
      try {
        expect((await run("--dir", d)).code).not.toBe(0);
      } finally {
        cleanFixtures();
      }
    });
    it("exit 2 fails", async () => {
      const d = mkFixture([{ p: "x.test.res.mjs", c: stub(2) }]);
      try {
        expect((await run("--dir", d)).code).not.toBe(0);
      } finally {
        cleanFixtures();
      }
    });
  });

  describe("timeout", () => {
    it("hanging child → non-zero", async () => {
      const d = mkFixture([{ p: "h.test.res.mjs", c: stubHanging() }]);
      try {
        expect((await run("--timeout", "200", "--dir", d)).code).not.toBe(0);
      } finally {
        cleanFixtures();
      }
    });
  });
});
