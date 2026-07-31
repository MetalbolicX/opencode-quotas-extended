// ANSI-aware text clip: scans value preserving ANSI SGR codes,
// truncates to (width - ellipsis.length) visible chars, pads to width.

// ESC character for ANSI SGR detection
let escChar = "\u001b"

// Manually strip ANSI SGR codes from text.
// Algorithm: scan for ESC + '[' + digits/+';' + 'm', skip those bytes.
// Returns only the visible (non-ANSI) characters.
let stripAnsi = (text: string): string => {
  let result = ref("")
  let i = ref(0)
  while i.contents < String.length(text) {
    let c = switch String.get(text, i.contents) {
    | Some(ch) => ch
    | None => ""
    }
    let nextC = switch String.get(text, i.contents + 1) {
    | Some(ch) => ch
    | None => ""
    }
    if c === escChar && nextC === "[" {
      // Skip the entire SGR sequence: ESC [ ... m
      let remaining = Js.String.substring(text, ~from=i.contents + 2, ~to_=String.length(text))
      let endM = String.indexOf(remaining, "m")
      if endM === -1 {
        // Unterminated SGR — skip remaining
        i := String.length(text)
      } else {
        // Skip past ESC + '[' + digits + 'm'
        i := i.contents + 2 + endM + 1
      }
    } else {
      result := result.contents ++ c
      i := i.contents + 1
    }
  }
  result.contents
}

let clip = (~width: int, value: string, ~ellipsis: string="…"): string => {
  if width <= 0 {
    ""
  } else if String.length(ellipsis) >= width {
    Js.String.substring(ellipsis, ~from=0, ~to_=width)
  } else {
    let visibleLen = String.length(stripAnsi(value))
    if visibleLen <= width {
      // No truncation needed — strip ANSI and pad
      String.padEnd(stripAnsi(value), width, " ")
    } else {
      // Truncation case: keep (width - ellipsis.length) visible chars
      let targetVisible = width - String.length(ellipsis)
      let result = ref("")
      let visCount = ref(0)
      let i = ref(0)
      let pendingSgr = ref("")
      let done = ref(false)

      while !done.contents && i.contents < String.length(value) && visCount.contents < targetVisible {
        let c = switch String.get(value, i.contents) {
        | Some(ch) => ch
        | None => ""
        }
        let nextC = switch String.get(value, i.contents + 1) {
        | Some(ch) => ch
        | None => ""
        }
        if c === "\x1b" && nextC === "[" {
          // Search for "m" starting from position i
          let remaining = Js.String.substring(value, ~from=i.contents, ~to_=String.length(value))
          let end = String.indexOf(remaining, "m")
          if end === -1 {
            done := true
          } else {
            let actualEnd = i.contents + end
            pendingSgr := Js.String.substring(value, ~from=i.contents, ~to_=actualEnd - i.contents + 1)
            i := actualEnd + 1
          }
        } else {
          if pendingSgr.contents !== "" {
            result := result.contents ++ pendingSgr.contents
            pendingSgr := ""
          }
          result := result.contents ++ c
          visCount := visCount.contents + 1
          i := i.contents + 1
        }
      }
      result.contents ++ ellipsis
    }
  }
}
