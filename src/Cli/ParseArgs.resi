// src/Cli/ParseArgs.resi
// CLI argument parser using node:util.parseArgs.

type parsedArgs = {
  list: bool,
  provider: option<string>,
  color: option<string>,
  mode: [#table | #json | #markdown],
  help: bool,
}

let parse: (array<string>) => result<parsedArgs, string>
