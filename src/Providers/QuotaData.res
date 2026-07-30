// src/Providers/QuotaData.res
// Local redeclaration of QuotaData -- port .resi is interface-only.
// Mirrors src/domain/types.ts QuotaData shape.

type rec quotaData = {
  id: string,
  providerName: string,
  used: float,
  limit: option<float>,
  unit: string,
  reset: option<string>,
  window: windowType,
  info: option<string>,
  modelId: option<string>,
}

// Window type mirrors Domain.window type
and windowType = [
  | #daily
  | #monthly
  | #rolling
  | #\"rolling-5h"
  | #\"rolling-1h"
  | #\"rolling-mcp"
  | #\"rolling-tokens"
  | #\"rolling-weekly"
]
