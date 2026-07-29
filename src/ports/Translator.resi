// Translator — all user-facing strings pass through this port (DIP).

type translator = {
  t: (string, option<dict<string>>) => string,
}
