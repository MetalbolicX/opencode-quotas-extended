import { defineConfig } from "rolldown";

export default defineConfig({
  input: "lib/es6/src/Bootstrap.res.mjs",
  output: {
    dir: "dist",
    format: "esm",
    entryFileNames: "cli/index.js",
    banner: "#!/usr/bin/env node",
  },
  platform: "node",
  external: [/^node:/, "ajv", "ajv-formats"],
});
