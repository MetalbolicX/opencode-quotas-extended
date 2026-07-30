// ANSI color name system — maps 16 standard color names to SGR codes.

type ansiColor = string
type colorMap = dict<ansiColor>

let colorMap: colorMap
let validColorNames: array<string>
let ansiColor: (string, string) => string
let dim: string => string
