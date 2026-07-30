// src/Cli/ParseArgs.res
// CLI argument parser using node:util.parseArgs.
// Flags: -l/--list, -p/--provider, -c/--color, -m/--mode, -h/--help.
// Strict: unknown options throw. Mutual exclusion of -l and -p validated.
// REQ-CLI-1..5, REQ-COLOR-3.

open Colors

type parsedArgs = {
  list: bool,
  provider: option<string>,
  color: option<string>,
  mode: [#table | #json | #markdown],
  help: bool,
}

// Use @module to generate ESM import - node:util.parseArgs is a named export
@module("node:util")
external parseArgsFn: {..} => {..} = "parseArgs"

let parse = (argv: array<string>): result<parsedArgs, string> => {
  // node:util.parseArgs throws in strict mode for unknown flags - catch it
  let parseResult: result<{..}, string> = try {
    let r = parseArgsFn(Obj.magic({
      "args": argv,
      "options": {
        "list": {"type": "boolean", "short": "l"},
        "provider": {"type": "string", "short": "p"},
        "color": {"type": "string", "short": "c"},
        "mode": {"type": "string", "short": "m"},
        "help": {"type": "boolean", "short": "h"},
      },
      "strict": true,
      "allowPositionals": false,
    }))
    Ok(r)
  } catch {
  | JsExn(e) => Error(String.make(e))
  | _ => Error("Unknown error")
  }

  switch parseResult {
  | Error(msg) => Error(msg)
  | Ok(result) =>
    let values: {..} = Obj.magic(result["values"])

    // Extract fields from values (JS undefined becomes None in ReScript option)
    let rawList: bool = Obj.magic(values["list"])
    let rawProvider: option<string> = Obj.magic(values["provider"])
    let rawColor: option<string> = Obj.magic(values["color"])
    let rawMode: option<string> = Obj.magic(values["mode"])
    let rawHelp: bool = Obj.magic(values["help"])

    // REQ-CLI-1: default to list=true when no provider is given
    let hasList = rawList === true
    let hasProvider = rawProvider !== None
    let list = hasList || !hasProvider

    // REQ-CLI-4: -l and -p are mutually exclusive
    if list && hasProvider {
      Error("Cannot combine -l/--list with -p/--provider")
    } else {
      // REQ-CLI-3: validate color against Colors.colorMap
      // "default" is valid (maps to \u001b[39m reset code) even though not in colorMap
      let colorValid = switch rawColor {
      | Some(c) => c === "default" || validColorNames->Array.some(v => v === c)
      | None => true
      }
      if colorValid === false {
        let c = switch rawColor { | Some(x) => x | None => "" }
        Error(`Invalid color: ${c}. Valid: ${validColorNames->Array.joinUnsafe(", ")}`)
      } else {
        // REQ-CLI-2: validate mode (default table)
        let mode: [#table | #json | #markdown] = switch rawMode {
        | Some("json") => #json
        | Some("markdown") => #markdown
        | _ => #table
        }
        let modeValid = switch rawMode {
        | Some("table") | Some("json") | Some("markdown") | None => true
        | _ => false
        }
        if modeValid === false {
          Error(`Invalid mode: ${Belt.Option.getWithDefault(rawMode, "undefined")}. Valid: table, json, markdown`)
        } else {
          Ok({
            list,
            provider: rawProvider,
            color: rawColor,
            mode,
            help: rawHelp === true,
          })
        }
      }
    }
  }
}
