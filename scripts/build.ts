#!/usr/bin/env bun

/**
 * scripts/build.ts — production build script
 *
 * Removes dist/, runs tsc, then prepends shebang to the CLI entry.
 * Run via: bun scripts/build.ts  (or: bun run build)
 */

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { rm, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join, dirname } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const DIST = join(ROOT, "dist");

async function run(command: string, args: string[], cwd: string): Promise<void> {
  const proc = Bun.spawn({ cmd: [command, ...args], cwd, stdout: "inherit", stderr: "inherit" });
  const code = await proc.exited;
  if (code !== 0) throw new Error(`\`${command} ${args.join(" ")}\` exited with code ${code}`);
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

  // Prepend shebang to CLI entry so it runs as a standalone executable.
  const cliPath = join(DIST, "cli", "index.js");
  if (existsSync(cliPath)) {
    const src = readFileSync(cliPath, "utf-8");
    if (!src.startsWith("#!/usr/bin/env bun")) {
      writeFileSync(cliPath, "#!/usr/bin/env bun\n" + src);
      console.log("[build] shebang prepended to dist/cli/index.js");
    }
  }
}

main().catch((err) => {
  console.error("[build] FAILED:", err.message);
  process.exit(1);
});
