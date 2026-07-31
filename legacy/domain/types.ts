// Core domain types — immutable, zero I/O imports.
// The domain layer has NO dependencies on adapters, ports, or Node built-ins.

export type RenderMode = "table" | "json" | "markdown";

/** Immutable quota data for a single tracked resource. */
export interface QuotaData {
  readonly id: string;
  readonly providerName: string;
  readonly used: number;
  /** null means unlimited */
  readonly limit: number | null;
  readonly unit: string;
  readonly reset: Date | null;
  readonly window: "daily" | "monthly" | "rolling" | "rolling-5h" | "rolling-mcp" | "rolling-tokens" | "rolling-weekly";
  readonly info?: string;
  /** Optional model identifier for providers that emit multiple rows per provider. */
  readonly modelId?: string;
}

/** Snapshot returned by the fetch pipeline — includes isolated per-provider failures. */
export interface QuotaSnapshot {
  readonly fetchedAt: Date;
  readonly data: readonly QuotaData[];
  /** Provider ID → error message. Present only when some providers failed. */
  readonly errors?: Readonly<Record<string, string>>;
}

/** Single history point for ETTL regression. */
export interface HistoryPoint {
  readonly timestamp: number; // Unix ms
  readonly used: number;
  readonly limit: number | null;
}
