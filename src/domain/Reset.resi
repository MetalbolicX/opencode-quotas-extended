// Reset.resi — public surface of the pure domain reset detection module.
// Exposes the reset detection function.
open Types

let detectReset: (historyPoint, quotaData) => bool
