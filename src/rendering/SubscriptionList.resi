// src/rendering/SubscriptionList.resi
// Pure renderer for the `-l/--list` subscription list. No I/O: the CLI collects
// the rows and prints whatever these functions return.

// One available subscription. `credential` is a source label
// (opencode | pi | claude-code | env | config | mmx), never a secret.
type row = {id: string, name: string, credential: string}

// S1: `## Available subscriptions (N)` + padded Markdown table + run hint.
// Table and markdown modes share this exact output.
let renderMarkdown: (~rows: array<row>) => string

// S3: 2-space-indented array of objects with only id, name, credential.
// No Markdown header/footer. No trailing newline (the CLI adds one).
let renderJson: (~rows: array<row>) => string
