@val external exit: int => unit = "process.exit"
@val external process: undefined<{..}> = "process"

let exit = code => {
  if typeof(process) != #undefined {
    exit(code)
  } else {
    Console.log(`# Exit code: ${code->Int.toString}`)
  }
}

let red = text => typeof(process) != #undefined ? `\u001b[31m${text}\u001b[0m` : text
let green = text => typeof(process) != #undefined ? `\u001b[32m${text}\u001b[0m` : text
let pink = text => typeof(process) != #undefined ? `\u001b[34m${text}\u001b[0m` : text
let yellow = text => typeof(process) != #undefined ? `\u001b[33m${text}\u001b[0m` : text
let grey = text => typeof(process) != #undefined ? `\u001b[2m${text}\u001b[0m` : text

let passText = green(`PASS`)
let failText = red(`FAIL`)
let todoText = yellow(`TODO`)

let running = ref(false)

let testCounter = ref(0)
let testPassedCounter = ref(0)
let testFailedCounter = ref(0)
let testTimeoutCounter = ref(0)

let testText = (name, index) => {
  let index = index->Int.toString
  let total = testCounter.contents->Int.toString
  Console.log(`${index}/${total}: ${name}`)
}

let passCounter = ref(0)
let failCounter = ref(0)

let total = () => (passCounter.contents + failCounter.contents)->Int.toString

let queue = ref(list{})

let startRunningTests = onEnd => {
  let tests = queue.contents->List.reverse
  let rec runNextTest = tests => {
    switch tests {
    | list{test, ...rest} => test(() => runNextTest(rest))
    | list{} => onEnd()->ignore
    }
  }
  runNextTest(tests)
}

let registerTest = test => {
  queue.contents = list{test, ...queue.contents}
}

let formatMessage = message =>
  switch message {
  | Some(message) => ` - ${message}`
  | None => grey(` - No message`)
  }

let assertion = (~message=?, ~operator=?, compare, a, b) => {
  if compare(a, b) {
    Int.Ref.increment(passCounter)
    Console.log(`  ${passText}${formatMessage(message)}`)
  } else {
    Int.Ref.increment(failCounter)
    Console.log(`  ${failText}${formatMessage(message)}`)
    Console.log(`    ---`)
    switch operator {
    | Some(operator) => Console.log(`    ${pink("operator")}: ${operator}`)
    | None => ()
    }
    Console.log2(`    ${pink("left")}: `, a)
    Console.log2(`    ${pink("right")}:`, b)
    Console.log(`    ...`)
  }
}

let doesNotThrow = (~message=?, func: unit => unit) => {
  try {
    func()
    Int.Ref.increment(passCounter)
    Console.log(`  ${passText}${formatMessage(message)}`)
  } catch {
  | exn =>
    Int.Ref.increment(failCounter)
    Console.log(`  ${failText}${formatMessage(message)}`)
    Console.log(`    ---`)
    Console.log(`    ${pink("operator")}: doesNotThrow`)
    Console.log2(`    ${pink("error")}:`, exn)
    Console.log(`    ...`)
  }
}

let throws = (~message=?, ~test: option<exn => bool>=?, func: unit => unit) => {
  try {
    func()
    Int.Ref.increment(failCounter)
    Console.log(`  ${failText}${formatMessage(message)}`)
  } catch {
  | exn =>
    switch test {
    | Some(test) if test(exn) == false =>
      Int.Ref.increment(failCounter)
      Console.log(`  ${failText}${formatMessage(message)}`)
    | _ =>
      Int.Ref.increment(passCounter)
      Console.log(`  ${passText}${formatMessage(message)}`)
    }
  }
}

let todo = message => {
  Console.log(`  ${todoText}${formatMessage(Some(message))}`)
}

let pass = (~message=?, ()) => {
  Int.Ref.increment(passCounter)
  Console.log(`  ${passText}${formatMessage(message)}`)
}

let fail = (~message=?, ()) => {
  Int.Ref.increment(failCounter)
  Console.log(`  ${failText}${formatMessage(message)}`)
  Console.log(`    ---`)
  Console.log(`    ${pink("operator")}: fail`)
  Console.log(`    ...`)
}

let testAsync = (name, ~timeout=5_000, func) => {
  if running.contents {
    Console.error(
      red(`# Cannot add testAsync("${name}", ...), tests must be defined at the top level`),
    )
  } else {
    Int.Ref.increment(testCounter)
    let index = testCounter.contents
    registerTest(resolve => {
      let failedAtStart = failCounter.contents
      let passedAtStart = passCounter.contents
      testText(name, index)
      try {
        let timeoutId = setTimeout(() => {
          let message = Some(`Timed out after ${timeout->Int.toString}ms`)
          Int.Ref.increment(testTimeoutCounter)
          Console.log(`  ${failText}${formatMessage(message)}`)
          resolve()
        }, timeout)
        func((~planned=?, ()) => {
          switch planned {
          | Some(planned) =>
            assertion(
              ~message="Correct assertion count",
              ~operator="planned",
              (a, b) => a == b,
              planned,
              passCounter.contents + failCounter.contents - (passedAtStart + failedAtStart),
            )
          | None => ()
          }
          clearTimeout(timeoutId)
          if failCounter.contents > failedAtStart {
            Int.Ref.increment(testFailedCounter)
          } else {
            Int.Ref.increment(testPassedCounter)
          }
          resolve()
        })
      } catch {
      | exn =>
        Console.error(exn)
        exit(1)
      }
    })
  }
}

let testAsyncWith = (~setup, ~teardown=?, name, ~timeout=?, func) => {
  testAsync(name, ~timeout?, callback => {
    let value = setup()
    func(value, (~planned=?, ()) => {
      try {
        switch teardown {
        | Some(teardown) => teardown(value)
        | None => ()
        }
      } catch {
      | exn =>
        Console.error(exn)
        exit(1)
      }
      callback(~planned?, ())
    })
  })
}

let createTestAsyncWith = (~setup, ~teardown=?) =>
  (name, ~timeout=?, func) => testAsyncWith(~setup, ~teardown?, name, ~timeout?, func)

let test = (name, func) => {
  if running.contents {
    Console.error(red(`# Cannot add test("${name}", ...), tests must be defined at the top level`))
  } else {
    Int.Ref.increment(testCounter)
    let index = testCounter.contents
    registerTest(resolve => {
      let failedAtStart = failCounter.contents

      testText(name, index)
      try {
        func()
      } catch {
      | exn =>
        Console.error(exn)
        exit(1)
      }
      if failCounter.contents > failedAtStart {
        Int.Ref.increment(testFailedCounter)
      } else {
        Int.Ref.increment(testPassedCounter)
      }
      resolve()
    })
  }
}

let testWith = (~setup, ~teardown=?, name, func) => {
  test(name, () => {
    let value = setup()
    func(value)
    switch teardown {
    | Some(teardown) => teardown(value)
    | None => ()
    }
  })
}

let createTestWith = (~setup, ~teardown=?) =>
  (name, func) => testWith(~setup, ~teardown?, name, func)

let autoBoot = ref(true)

let runTests = () => {
  running := true

  startRunningTests(() => {
    Console.log(``)
    Console.log(grey(`# Ran ${testCounter.contents->Int.toString} tests (${total()} assertions)`))
    Console.log(grey(`# ${testPassedCounter.contents->Int.toString} passed`))
    Console.log(
      grey(
        `# ${(testFailedCounter.contents + testTimeoutCounter.contents)
            ->Int.toString} failed${testTimeoutCounter.contents > 0
            ? ` (${testTimeoutCounter.contents->Int.toString} timed out)`
            : ``}`,
      ),
    )

    if testFailedCounter.contents + testTimeoutCounter.contents > 0 {
      exit(1)
    } else {
      exit(0)
    }
  })
}

// Disable autoBoot when imported as a module
autoBoot := false
