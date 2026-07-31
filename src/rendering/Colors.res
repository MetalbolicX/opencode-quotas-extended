// ANSI color name system — maps 16 standard color names to SGR codes.
// Used by StatusBar to apply color to the usage progress bar.

type ansiColor = string
type colorMap = dict<ansiColor>

let colorMap: colorMap = Dict.fromArray([
  ("black", "30"),
  ("red", "31"),
  ("green", "32"),
  ("yellow", "33"),
  ("blue", "34"),
  ("magenta", "35"),
  ("cyan", "36"),
  ("white", "37"),
  ("brightBlack", "90"),
  ("brightRed", "91"),
  ("brightGreen", "92"),
  ("brightYellow", "93"),
  ("brightBlue", "94"),
  ("brightMagenta", "95"),
  ("brightCyan", "96"),
  ("brightWhite", "97"),
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
  | Some(code) => {
      // colorMap stores the full ANSI SGR code (e.g. "30" for black).
      // Build the sequence: ESC + [ + code + m + text + ESC + [ + 0 + m
      let esc = "\u001b"
      `${esc}[${code}m${text}${esc}[0m`
    }
  }
}

let dim = (text: string): string => `${dimSgr}${text}${resetSgr}`
