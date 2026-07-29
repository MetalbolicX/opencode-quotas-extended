// Logger — application logs through this port (DIP).

type logger = {
  debug: (string, option<{ .. }>) => unit,
  info: (string, option<{ .. }>) => unit,
  warn: (string, option<{ .. }>) => unit,
  error: (string, option<{ .. }>) => unit,
}

/** Silent no-op logger — used as the default when no logger is injected. */
let noopLogger: logger = {
  debug: (_, _) => (),
  info: (_, _) => (),
  warn: (_, _) => (),
  error: (_, _) => (),
}
