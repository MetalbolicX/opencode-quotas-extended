// ANSI color name system — maps 16 standard color names to SGR codes.
// Used by StatusBar to apply color to the usage progress bar.

type ansiColor = string
type colorMap = dict<ansiColor>

let colorMap: colorMap = Dict.fromArray([
  ("black", "\u001b[30m"),
  ("red", "\u001b[31m"),
  ("green", "\u001b[32m"),
  ("yellow", "\u001b[33m"),
  ("blue", "\u001b[34m"),
  ("magenta", "\u001b[35m"),
  ("cyan", "\u001b[36m"),
  ("white", "\u001b[37m"),
  ("brightBlack", "\u001b[90m"),
  ("brightRed", "\u001b[91m"),
  ("brightGreen", "\u001b[92m"),
  ("brightYellow", "\u001b[93m"),
  ("brightBlue", "\u001b[94m"),
  ("brightMagenta", "\u001b[95m"),
  ("brightCyan", "\u001b[96m"),
  ("brightWhite", "\u001b[97m"),
])

let validColorNames: array<string> = Dict.keysToArray(colorMap)

let dimSgr = "\u001b[2m"
let resetSgr = "\u001b[0m"

let ansiColor = (name: string, text: string): string => {
  switch Dict.get(colorMap, name) {
  | None =>
    let valid = validColorNames->Array.joinUnsafe(", ")
    let msg = `Invalid color name: "${name}". Valid: ${valid}`
    JsError.throwWithMessage(msg)
  | Some(code) => `\u001b[${code}m${text}\u001b[0m`
  }
}

let dim = (text: string): string => `${dimSgr}${text}${resetSgr}`
