#!/usr/bin/env node
// scripts/run-tests.mjs — Aggregate runner for ReScript test files.
// See openspec/changes/rescript-cutover/specs/test-runner/spec.md.
//
// Runs every compiled ReScript test module (lib/es6/**/*Tests.res.mjs and
// lib/es6/**/*.test.res.mjs) as a separate Node child process, aggregates
// exit codes, and prints a per-file pass/fail summary.
//
// Execution is SEQUENTIAL (not parallel) to keep output deterministic and
// simplify debugging. An optional --parallel flag may be added in future.
//
// Exit codes:
//   0  all children exited 0
//   1  one or more children exited non-zero
//   2  glob error (no matching files is NOT an error — exits 0 with warning)

import { readdirSync } from "node:fs";
import { join, relative, isAbsolute, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

// ── Paths ─────────────────────────────────────────────────────────────────────

const PROJECT_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));

// ── Config ───────────────────────────────────────────────────────────────────

const DEFAULT_TIMEOUT_MS = 30_000;

const GLOB_PATTERNS = [
  // *Tests.res.mjs  (e.g. ConfigLoaderTests.res.mjs)
  /Tests\.res\.mjs$/,
  // *.test.res.mjs  (e.g. Bootstrap.test.res.mjs)
  /\.test\.res\.mjs$/,
];

// ── CLI ─────────────────────────────────────────────────────────────────────

function printHelp() {
  console.log(
    `run-tests.mjs — Aggregate runner for ReScript test files.

Usage:
  node scripts/run-tests.mjs [options]

Options:
  --help            Show this help and exit.
  --timeout <ms>    Per-file timeout in milliseconds (default: ${DEFAULT_TIMEOUT_MS}).
  --dir <path>      Root directory to search for compiled tests
                    (default: lib/es6/ under PROJECT_ROOT).

Environment variables:
  RES_TEST_TIMEOUT_MS   Per-file timeout in milliseconds (default: 30000).

Exit codes:
  0   All tests passed.
  1   One or more test files failed.
  2   Glob error (directory not found, etc.).
`
  );
}

// ── Glob ─────────────────────────────────────────────────────────────────────

/**
 * Recursively collect all file paths under `root` that match any GLOB_PATTERNS.
 * Returns absolute paths, sorted lexicographically.
 */
function discoverTestFiles(root) {
  const results = [];

  function walk(dir) {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      // Directory not found or unreadable — propagate to caller
      return false;
    }

    for (const entry of entries) {
      const fullPath = join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath);
      } else if (entry.isFile()) {
        if (GLOB_PATTERNS.some((re) => re.test(entry.name))) {
          results.push(fullPath);
        }
      }
    }
    return true;
  }

  const ok = walk(root);
  if (!ok) return null; // indicates glob error
  results.sort(); // deterministic order
  return results;
}

// ── Per-file runner ──────────────────────────────────────────────────────────

/**
 * Spawn one Node child for `testPath`, wait for it to finish, and return
 * the result { passed, exitCode, signal, timedOut }.
 */
function runFile(testPath, timeoutMs) {
  return new Promise((resolve) => {
    const child = spawn("node", [testPath], {
      cwd: PROJECT_ROOT,
      stdio: ["ignore", "pipe", "pipe"],
      timeout: undefined, // we handle timeout manually
    });

    // Relay child output to terminal (preserve debuggability)
    child.stdout.on("data", (d) => process.stdout.write(d));
    child.stderr.on("data", (d) => process.stderr.write(d));

    const timer = setTimeout(() => {
      // SIGTERM first, then SIGKILL after a short grace
      child.kill("SIGTERM");
      setTimeout(() => {
        if (!child.killed) child.kill("SIGKILL");
      }, 500);
    }, timeoutMs);

    child.on("close", (code, signal) => {
      clearTimeout(timer);
      const timedOut = !child.exitCode && !code && signal === "SIGTERM";
      resolve({
        passed: code === 0 && signal === null,
        exitCode: code,
        signal,
        timedOut,
      });
    });

    child.on("error", (err) => {
      clearTimeout(timer);
      resolve({ passed: false, exitCode: null, signal: null, timedOut: false });
    });
  });
}

// ── Summary ──────────────────────────────────────────────────────────────────

function printSummary(results, totalMs) {
  const total = results.length;
  const passed = results.filter((r) => r.passed).length;
  const failed = total - passed;

  console.log("");
  if (failed === 0) {
    console.log(
      `ReScript tests: ${total} file${total !== 1 ? "s" : ""}, all passed (${totalMs}ms)`
    );
  } else {
    console.log(
      `ReScript tests: ${total} files, ${passed} passed, ${failed} failed (${totalMs}ms)`
    );
  }
}

// ── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  // Parse minimal args
  let timeoutMs = DEFAULT_TIMEOUT_MS;
  let root = join(PROJECT_ROOT, "lib", "es6");

  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help") {
      printHelp();
      process.exit(0);
    } else if (arg === "--timeout" && i + 1 < args.length) {
      timeoutMs = parseInt(args[++i], 10);
      if (isNaN(timeoutMs) || timeoutMs <= 0) {
        console.error("run-tests: --timeout must be a positive integer");
        process.exit(2);
      }
    } else if (arg === "--dir" && i + 1 < args.length) {
      root = args[++i];
      if (!isAbsolute(root)) {
        root = join(PROJECT_ROOT, root);
      }
    }
  }

  // Honor env var override
  if (process.env.RES_TEST_TIMEOUT_MS) {
    const envMs = parseInt(process.env.RES_TEST_TIMEOUT_MS, 10);
    if (!isNaN(envMs) && envMs > 0) timeoutMs = envMs;
  }

  const startMs = Date.now();

  // Discover files
  const files = discoverTestFiles(root);

  if (files === null) {
    console.log(`run-tests: glob error — could not read directory: ${root}`);
    process.exit(2);
  }

  if (files.length === 0) {
    console.log("run-tests: no test files found.");
    process.exit(1); // non-zero: not a silent pass
  }

  // Run each file sequentially
  const results = [];
  for (const file of files) {
    const rel = relative(PROJECT_ROOT, file);
    const result = await runFile(file, timeoutMs);
    results.push({ file: rel, ...result });

    if (result.timedOut) {
      console.log(`TIMEOUT ${rel} (${timeoutMs}ms exceeded)`);
    } else if (result.passed) {
      console.log(`PASS ${rel}`);
    } else {
      const how =
        result.signal !== null
          ? `signal ${result.signal}`
          : `exit ${result.exitCode}`;
      console.log(`FAIL ${rel} (${how})`);
    }
  }

  const totalMs = Date.now() - startMs;
  printSummary(results, totalMs);

  const anyFailed = results.some((r) => !r.passed);
  process.exit(anyFailed ? 1 : 0);
}

main().catch((err) => {
  console.error("run-tests: unexpected error:", err.message);
  process.exit(2);
});
