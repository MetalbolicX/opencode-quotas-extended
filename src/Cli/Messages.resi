// Diagnostic string formatters for credential and provider errors.

let formatNoSubscriptions: unit => string
let formatNoCredentialsForProvider: (string, array<string>) => string
let formatProviderFetchErrors: dict<string> => string
let formatMissingAuthJson: string => string
