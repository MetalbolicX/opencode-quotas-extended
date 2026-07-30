// src/Cli/Cli.resi
// CLI entry point — dispatches to list or provider mode.

type runResult = {
  stdout: string,
  stderr: string,
  exitCode: int,
}

let run: (array<string>) => Promise.t<runResult>
let main: (array<string>) => Promise.t<unit>
let usageText: string
