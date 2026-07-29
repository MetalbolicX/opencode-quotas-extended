// Status thresholds + progress bar. Defaults: OK < 0.5 | WRN [0.5, 0.8) | ERR [0.8, ∞). Unlimited → OK.
open Colors

type statusCode = | @as("OK") OK | @as("WRN") WRN | @as("ERR") ERR | @as("UNK") UNK

type statusResult = {
  code: statusCode,
  ratio: option<float>,
}

type gradient = {
  threshold: float,
  color: string,
}

type barOptions = {
  width: option<float>,
  filledChar: option<string>,
  emptyChar: option<string>,
  colorName: option<string>,
  framed: option<bool>,
  colorSplit: option<string>,
}

let defaultGradients: array<gradient> = [
  { threshold: 0.5, color: "green" },
  { threshold: 0.8, color: "yellow" },
  { threshold: 1.0, color: "red" },
]

let statusCodeOfColor = (c: string): statusCode => {
  switch c {
  | "green" => OK
  | "yellow" => WRN
  | "red" => ERR
  | _ => UNK
  }
}

let getStatus = (
  used: float,
  limit: option<float>,
  ~gradients: array<gradient>=defaultGradients,
): statusResult => {
  switch limit {
  | None => { code: OK, ratio: None }
  | Some(lim) =>
    if used === 0.0 {
      { code: OK, ratio: Some(0.0) }
    } else {
      let ratio = used /. lim
      // Find first matching gradient
      let matchingIdx = {
        let found = ref(-1)
        for i in 0 to Array.length(gradients) - 1 {
          switch gradients[i] {
          | Some(g) if ratio < g.threshold => found := i
          | _ => ()
          }
        }
        found.contents
      }
      if matchingIdx >= 0 {
        switch gradients[matchingIdx] {
        | Some(g) => { code: statusCodeOfColor(g.color), ratio: Some(ratio) }
        | None => { code: UNK, ratio: Some(ratio) }
        }
      } else if Array.length(gradients) > 0 {
        switch gradients[Array.length(gradients) - 1] {
        | Some(last) => { code: statusCodeOfColor(last.color), ratio: Some(ratio) }
        | None => { code: UNK, ratio: Some(ratio) }
        }
      } else {
        { code: UNK, ratio: Some(ratio) }
      }
    }
  }
}

let renderBar = (ratio: float, ~opts: option<barOptions>=?): string => {
  let opts' = switch opts {
  | Some(o) => o
  | None => {
      width: None,
      filledChar: None,
      emptyChar: None,
      colorName: None,
      framed: None,
      colorSplit: None,
    }
  }
  let w = switch opts'.width {
  | Some(w') => w'
  | None => 10.0
  }
  let fc = switch opts'.filledChar {
  | Some(fc') => fc'
  | None => "█"
  }
  let ec = switch opts'.emptyChar {
  | Some(ec') => ec'
  | None => "."
  }

  let clamped = Math.max(Math.min(ratio, 1.0), 0.0)
  let filled = Math.round(clamped *. w)
  let emptyFloat = w -. filled

  let useColorSplit = opts'.colorSplit === Some("filled") && opts'.colorName !== None

  let (filledPart, emptyPart) = if useColorSplit {
    let colorName = switch opts'.colorName {
    | Some(cn) => cn
    | None => "white"
    }
    let filledInt = Belt.Float.toInt(filled)
    let emptyInt = Belt.Float.toInt(emptyFloat)
    let filledStr = {
      let rec repeat = (n, acc) => if n <= 0 { acc } else { repeat(n - 1, acc ++ fc) }
      repeat(filledInt, "")
    }
    let emptyStr = {
      let rec repeat = (n, acc) => if n <= 0 { acc } else { repeat(n - 1, acc ++ ec) }
      repeat(emptyInt, "")
    }
    (ansiColor(colorName, filledStr), dim(emptyStr))
  } else if opts'.colorName !== None {
    let colorName = switch opts'.colorName {
    | Some(cn) => cn
    | None => "white"
    }
    let filledInt = Belt.Float.toInt(filled)
    let emptyInt = Belt.Float.toInt(emptyFloat)
    let bar = {
      let rec repeatFilled = (n, acc) => if n <= 0 { acc } else { repeatFilled(n - 1, acc ++ fc) }
      let rec repeatEmpty = (n, acc) => if n <= 0 { acc } else { repeatEmpty(n - 1, acc ++ ec) }
      repeatFilled(filledInt, "") ++ repeatEmpty(emptyInt, "")
    }
    (ansiColor(colorName, bar), "")
  } else {
    let filledInt = Belt.Float.toInt(filled)
    let emptyInt = Belt.Float.toInt(emptyFloat)
    let filledStr = {
      let rec repeat = (n, acc) => if n <= 0 { acc } else { repeat(n - 1, acc ++ fc) }
      repeat(filledInt, "")
    }
    let emptyStr = {
      let rec repeat = (n, acc) => if n <= 0 { acc } else { repeat(n - 1, acc ++ ec) }
      repeat(emptyInt, "")
    }
    (filledStr ++ emptyStr, "")
  }

  let bar = filledPart ++ emptyPart
  switch opts'.framed {
  | Some(true) => `[${bar}] `
  | _ => bar
  }
}
