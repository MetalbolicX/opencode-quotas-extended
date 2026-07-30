// ANSI-aware text clip: scans value preserving ANSI SGR codes,
// truncates to (width - ellipsis.length) visible chars, pads to width.

let sgrRe = %re("/\x1b\\[[0-9;]*m/g")

let stripAnsi = (text: string): string => {
  Js.String.replaceByRe(sgrRe, "", text)
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
