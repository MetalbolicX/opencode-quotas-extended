// All domain tests consolidated runner
// Each module's test file registers tests via RescriptTest.test()
open RescriptTest

// Test files that exist in lib/es6 (compiled by rescript build):
// - lib/es6/src/domain/Reset.test.res.mjs
// - lib/es6/src/domain/AggregationDefaults.test.res.mjs
// - lib/es6/src/domain/Prediction.test.res.mjs
// - lib/es6/src/domain/Aggregation.test.res.mjs
// - lib/es6/src/domain/Types.test.res.mjs

// Note: Each individual test file calls runTests() which exits the process.
// The pnpm test:domain script runs all of them sequentially.

// Placeholder — actual tests live in individual test files
test("placeholder: domain tests run via pnpm test:domain", () => {
  assertion(
    ~message="see package.json test:domain script",
    (a, b) => a == b,
    true,
    true,
  )
})

runTests()
