open RescriptTest

type greeting = {
  name: string,
}

let hello = (g: greeting): string => "Hello, " ++ g.name ++ "!"

// Disable auto-boot since we control test execution explicitly
autoBoot := false

// Test 1: hello returns correct greeting
test("hello returns correct greeting", () => {
  let result = hello({name: "World"})
  assertion(
    ~message=`Expected "Hello, World!", got "${result}"`,
    (a, b) => a == b,
    result,
    "Hello, World!",
  )
})

// Test 2: hello handles empty string name
test("hello handles empty string name", () => {
  let result = hello({name: ""})
  assertion(~message=`Expected "Hello, !", got "${result}"`, (a, b) => a == b, result, "Hello, !")
})

// Test 3: hello handles special characters
test("hello handles special characters", () => {
  let result = hello({name: "🎉"})
  assertion(
    ~message=`Expected "Hello, 🎉!", got "${result}"`,
    (a, b) => a == b,
    result,
    "Hello, 🎉!",
  )
})

// Run tests and exit with appropriate code
runTests()
