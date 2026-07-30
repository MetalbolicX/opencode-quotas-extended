// src/Cli/ParseArgsTests.res
// Tests for ParseArgs: P1–P8 scenarios from SDD spec.
// REQ-CLI-1..5: strict parseArgs with -l/-p/-c/-m/-h flags.
open RescriptTest
open ParseArgs

autoBoot := false

// P1: empty argv → list:true, mode:table, help:false
test("P1: empty argv defaults to list:true, table mode, help:false", () => {
  let result = parse([])
  switch result {
  | Ok(args) => {
      assertion(~message="list is true by default", (a, b) => a == b, args.list, true)
      assertion(~message="mode is table by default", (a, b) => a == b, args.mode, #table)
      assertion(~message="help is false by default", (a, b) => a == b, args.help, false)
      assertion(~message="provider is None", (a, b) => a == b, Belt.Option.isNone(args.provider), true)
    }
  | Error(e) => assertion(~message="should not error: " ++ e, (a, b) => a == b, false, true)
  }
})

// P2: -l flag → list:true
test("P2: -l flag sets list:true", () => {
  let result = parse(["-l"])
  switch result {
  | Ok(args) => assertion(~message="list is true with -l", (a, b) => a == b, args.list, true)
  | Error(e) => assertion(~message="should not error: " ++ e, (a, b) => a == b, false, true)
  }
})

// P3: -p provider → list:false, provider set
test("P3: -p openai sets provider and list:false", () => {
  let result = parse(["-p", "openai"])
  switch result {
  | Ok(args) => {
      assertion(~message="list is false with -p", (a, b) => a == b, args.list, false)
      assertion(~message="provider is openai", (a, b) => a == b, args.provider, Some("openai"))
    }
  | Error(e) => assertion(~message="should not error: " ++ e, (a, b) => a == b, false, true)
  }
})

// P4: -l and -p together → Error
test("P4: -l and -p together throws mutual exclusion error", () => {
  let result = parse(["-l", "-p", "openai"])
  switch result {
  | Error(msg) => assertion(~message="error mentions mutual exclusion", (a, b) => a == b, true, String.includes(msg, "Cannot combine"))
  | Ok(_) => assertion(~message="should not be Ok", (a, b) => a == b, false, true)
  }
})

// P5a: valid color names (16 standard + default) are accepted
test("P5a: valid color names are accepted", () => {
  // Colors.validColorNames has 16 standard colors; "default" is also valid
  let allOk = Colors.validColorNames->Array.every(color => {
    switch parse(["-c", color]) {
    | Ok(args) => args.color == Some(color)
    | Error(_) => false
    }
  })
  assertion(~message="all 16 standard colors accepted", (a, b) => a == b, true, allOk)
})

// P5b+: "default" is also valid (special reset color)
test("P5b+: default color is accepted", () => {
  let result = parse(["-c", "default"])
  switch result {
  | Ok(args) => assertion(~message="default color accepted", (a, b) => a == b, args.color, Some("default"))
  | Error(_) => assertion(~message="default should not error", (a, b) => a == b, false, true)
  }
})

// P5b: invalid color → Error
test("P5b: invalid color throws error", () => {
  let result = parse(["-c", "notacolor"])
  switch result {
  | Error(msg) => assertion(~message="error mentions invalid color", (a, b) => a == b, true, String.includes(msg, "Invalid color"))
  | Ok(_) => assertion(~message="should not be Ok", (a, b) => a == b, false, true)
  }
})

// P6a: valid modes are accepted
test("P6a: -m json|markdown|table accepted", () => {
  let jsonResult = parse(["-m", "json"])
  let mdResult = parse(["-m", "markdown"])
  let tableResult = parse(["-m", "table"])
  let allOk = jsonResult->Belt.Result.isOk && mdResult->Belt.Result.isOk && tableResult->Belt.Result.isOk
  assertion(~message="all modes accepted", (a, b) => a == b, true, allOk)
})

// P6b: invalid mode → Error
test("P6b: invalid mode throws error", () => {
  let result = parse(["-m", "xml"])
  switch result {
  | Error(msg) => assertion(~message="error mentions invalid mode", (a, b) => a == b, true, String.includes(msg, "Invalid mode"))
  | Ok(_) => assertion(~message="should not be Ok", (a, b) => a == b, false, true)
  }
})

// P7: -h/--help sets help:true
test("P7: -h sets help:true", () => {
  let result = parse(["-h"])
  switch result {
  | Ok(args) => assertion(~message="help is true with -h", (a, b) => a == b, args.help, true)
  | Error(e) => assertion(~message="should not error: " ++ e, (a, b) => a == b, false, true)
  }
})

// P8: unknown flag throws in strict mode
test("P8: unknown flag throws in strict mode", () => {
  let result = parse(["--unknown-flag"])
  switch result {
  | Error(_) => assertion(~message="unknown flag throws error", (a, b) => a == b, true, true)
  | Ok(_) => assertion(~message="should not be Ok", (a, b) => a == b, false, true)
  }
})

// Bonus: --list and --provider long forms
test("Bonus: --list and --provider long forms work", () => {
  let listResult = parse(["--list"])
  let providerResult = parse(["--provider", "openai"])
  let bothResult = parse(["--list", "--provider", "openai"])
  assertion(~message="--list is Ok", (a, b) => a == b, true, listResult->Belt.Result.isOk)
  assertion(~message="--provider is Ok", (a, b) => a == b, true, providerResult->Belt.Result.isOk)
  assertion(~message="both is Error", (a, b) => a == b, true, bothResult->Belt.Result.isError)
})

// Bonus: -m default is table
test("Bonus: -m omitted defaults to table", () => {
  let result = parse([])
  switch result {
  | Ok(args) => assertion(~message="mode defaults to table", (a, b) => a == b, args.mode, #table)
  | Error(e) => assertion(~message="should not error: " ++ e, (a, b) => a == b, false, true)
  }
})

let () = runTests()
