// QuotaProvider — each adapter implements this port.
// The domain depends ONLY on this interface (DIP).

import type { QuotaData } from "../domain/types.js";

export interface QuotaProvider {
  readonly id: string;
  readonly displayName: string;
  readonly category: string;
  /** "api" | "oauth" | "wellknown" | "env" */
  readonly authStrategy: "api" | "oauth" | "wellknown" | "env";

  /**
   * Returns true when the provider is available (credentials present, network reachable, etc.).
   * Adapters resolve their own credentials via the injected CredentialSource.
   */
  isAvailable(): Promise<boolean>;

  /**
   * Fetches quota data for this provider. Returns an array (one entry per tracked resource).
   * Adapters resolve their own credentials via the injected CredentialSource.
   */
  fetchQuotas(): Promise<QuotaData[]>;
}
