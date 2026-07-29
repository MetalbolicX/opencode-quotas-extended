type greeting = {
  name: string
}

let hello = (g: greeting): string => "Hello, " ++ g.name ++ "!"

let _ = hello({ name: "ReScript" })
