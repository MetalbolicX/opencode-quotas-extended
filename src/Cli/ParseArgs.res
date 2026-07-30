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

// Types for typed FFI with node:util.parseArgs
// parseArgs returns an object with a 'values' field containing parsed options.
// We use a closed type with optional fields for the values object.
type parseArgsValues = {
  list: option<bool>,
  provider: option<string>,
  color: option<string>,
  mode: option<string>,
  help: option<bool>,
}

// Use @module to generate ESM import - node:util.parseArgs is a named export
@module("node:util")
external parseArgsFn: {..} => {..} = "parseArgs"

// Accessors for the values object and its fields
// All option fields are Nullable.t because JS parseArgs returns undefined when
// a flag is not provided. Nullable.toOption converts to ReScript option.
@get external valuesOf: {..} => parseArgsValues = "values"
@get external getList: parseArgsValues => Nullable.t<bool> = "list"
@get external getProvider: parseArgsValues => Nullable.t<string> = "provider"
@get external getColor: parseArgsValues => Nullable.t<string> = "color"
@get external getMode: parseArgsValues => Nullable.t<string> = "mode"
@get external getHelp: parseArgsValues => Nullable.t<bool> = "help"

let parse = (argv: array<string>): result<parsedArgs, string> => {
  // node:util.parseArgs throws in strict mode for unknown flags - catch it
  let parseResult: result<{..}, string> = try {
    let r = parseArgsFn({
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
    })
    Ok(r)
  } catch {
  | JsExn(e) => Error(String.make(e))
  | _ => Error("Unknown error")
  }

  switch parseResult {
  | Error(msg) => Error(msg)
  | Ok(result) =>
    let values = valuesOf(result)

    // Extract fields from values (JS undefined → None via Nullable.toOption)
    let rawList: bool = Belt.Option.getWithDefault(Nullable.toOption(getList(values)), false)
    let rawProvider: option<string> = Nullable.toOption(getProvider(values))
    let rawColor: option<string> = Nullable.toOption(getColor(values))
    let rawMode: option<string> = Nullable.toOption(getMode(values))
    let rawHelp: bool = Belt.Option.getWithDefault(Nullable.toOption(getHelp(values)), false)

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
