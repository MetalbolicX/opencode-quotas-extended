// QuotaProvider — each adapter implements this port.
// The domain depends ONLY on this interface (DIP).

import type { FetchContext } from "./http.js";
import type { QuotaData } from "../domain/types.js";

export interface QuotaProvider {
  readonly id: string;
  readonly displayName: string;
  readonly category: string;
  /** "api" | "oauth" | "wellknown" | "env" */
  readonly authStrategy: "api" | "oauth" | "wellknown" | "env";

  /** Returns true when the provider is available (credentials present, network reachable, etc.) */
  isAvailable(credentials: unknown, ctx: FetchContext): Promise<boolean>;

  /** Fetches quota data for this provider. Returns an array (one entry per tracked resource). */
  fetchQuotas(credentials: unknown, ctx: FetchContext): Promise<QuotaData[]>;
}
