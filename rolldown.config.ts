import { defineConfig } from "rolldown";

export default defineConfig({
  input: "src/cli/index.ts",
  output: {
    dir: "dist",
    format: "esm",
    entryFileNames: "cli/index.js",
    banner: "#!/usr/bin/env node",
  },
  platform: "node",
  external: [/^node:/, "ajv", "ajv-formats"],
});
