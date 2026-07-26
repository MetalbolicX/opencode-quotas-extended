// HTTP port — abstracts the HTTP client used by provider adapters.
// In tests, this is mocked so no live network calls occur.

export interface FetchContext {
  readonly signal?: AbortSignal;
}

export interface HttpRequest {
  readonly url: string;
  readonly method: "GET" | "POST" | "PUT" | "DELETE";
  readonly headers?: Record<string, string>;
  readonly body?: unknown;
}

export interface HttpClient {
  request<T>(request: HttpRequest, options: {
    readonly timeoutMs: number;
    readonly retries: number;
    readonly redact: true; // always redact secrets in logs
  }): Promise<T>;
}
