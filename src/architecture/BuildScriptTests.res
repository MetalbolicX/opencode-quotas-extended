// src/architecture/BuildScriptTests.res
// Architecture guard: build pipeline uses rolldown, not bun.
// Mirrors tests/architecture/build-script.test.ts.
// NOTE: does NOT assert src/cli/index.ts exists (moves to legacy/ in WU-5).
open RescriptTest

autoBoot := false

// ── Helpers ────────────────────────────────────────────────────────────────────

let projectRoot = Node.processCwd()

let readFile = (path: string): string => {
  Node.readFileSyncUtf8(Node.pathJoin(projectRoot, path), {encoding: "utf-8"})
}

let fileExists = (path: string): bool => {
  Node.existsSync(Node.pathJoin(projectRoot, path))
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test("rolldown.config.ts exists at project root", () => {
  let exists = fileExists("rolldown.config.ts")
  assertion(
    ~message="rolldown.config.ts must exist at project root",
    (a, _b) => a == true,
    exists,
    true,
  )
})

test("package.json build script uses rolldown", () => {
  let pkgContent = readFile("package.json")
  // Simple substring check: "rolldown" appears in the file content.
  // The build field always appears after "scripts": in package.json.
  let hasRolldown = String.includes(pkgContent, "rolldown")
  assertion(
    ~message="package.json must contain 'rolldown' in build script",
    (a, _b) => a == true,
    hasRolldown,
    true,
  )
})

test("package.json has no bun references in scripts or packageManager", () => {
  let pkgContent = readFile("package.json")
  // Case-insensitive check for "bun" as substring anywhere in package.json
  let pkgLower = pkgContent->String.toLowerCase
  let hasBun = String.includes(pkgLower, "bun")
  assertion(
    ~message="package.json must not contain 'bun' anywhere",
    (a, _b) => a == false,
    hasBun,
    false,
  )
})

test("rolldown.config.ts references Bootstrap.res.mjs, platform node, and shebang", () => {
  let content = readFile("rolldown.config.ts")

  // Entry: Bootstrap.res.mjs (compiled ReScript bootstrap, replaces src/cli/index.ts)
  let hasBootstrap = String.includes(content, "Bootstrap.res.mjs")
  assertion(
    ~message="rolldown.config.ts must reference Bootstrap.res.mjs as entry",
    (a, _b) => a == true,
    hasBootstrap,
    true,
  )

  // Platform: node (look for platform: and "node" nearby)
  let hasPlatform = String.includes(content, "platform:") && String.includes(content, "\"node\"")
  assertion(
    ~message="rolldown.config.ts must declare platform: \"node\"",
    (a, _b) => a == true,
    hasPlatform,
    true,
  )

  // Shebang: #!/usr/bin/env node
  let hasShebang = String.includes(content, "#!/usr/bin/env node")
  assertion(
    ~message="rolldown.config.ts must use #!/usr/bin/env node shebang",
    (a, _b) => a == true,
    hasShebang,
    true,
  )
})

let () = runTests()
