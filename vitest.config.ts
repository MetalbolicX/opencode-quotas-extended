import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
    include: ["tests/**/*.test.ts", "tests/**/*.spec.ts"],
    coverage: {
      provider: "v8",
      include: ["src/**/*.ts"],
      exclude: [
        "src/**/*.d.ts",
        "src/**/types.ts",
      ],
      reporter: ["text", "lcov"],
      thresholds: {
        // Per-design: domain core (src/domain/) requires ≥85%
        // Overall project requires ≥70%
        lines: 70,
        functions: 70,
        branches: 70,
        statements: 70,
        perFile: false,
      },
    },
  },
});
