// Bootstrap.res — main module detection + CLI entry point
// Mirrors the TS bootstrap in src/cli/index.ts (isMainModule guard + Cli.main call)

let isMainModule = (): bool => {
  switch Node.processArgv[1] {
  | None => false
  | Some(argv1) =>
    let here = Node.realpathSync(Node.fileURLToPath(Node.importMetaUrl()))
    let invoked = Node.realpathSync(Node.pathResolve(argv1))
    here === invoked
  }
}

let main = (): unit => {
  // Cli.main slices argv (drops node/rescript + script path)
  Cli.main(Node.processArgv)
}

if isMainModule() {
  main()
}
