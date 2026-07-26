#!/usr/bin/env bun

/**
 * scripts/build.ts — production build script
 *
 * Removes dist/, then runs tsc to emit declaration files and JS output.
 * Run via: bun scripts/build.ts  (or: bun run build)
 */

import { rm, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join, dirname } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const DIST = join(ROOT, "dist");

async function run(command: string, args: string[], cwd: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, stdio: "inherit" });
    child.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`\`${command} ${args.join(" ")}\` exited with code ${code}`));
    });
    child.on("error", reject);
  });
}

async function main() {
  // Clean dist/
  if (existsSync(DIST)) {
    await rm(DIST, { recursive: true, force: true });
    console.log("[build] Removed dist/");
  }
  await mkdir(DIST, { recursive: true });

  // TypeScript compilation (emits .js + .d.ts + source maps)
  await run("tsc", ["--project", join(ROOT, "tsconfig.json")], ROOT);
  console.log("[build] tsc complete");
}

main().catch((err) => {
  console.error("[build] FAILED:", err.message);
  process.exit(1);
});
