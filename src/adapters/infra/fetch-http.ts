// FetchHttpClient — HttpClient adapter using global fetch (Node 18+ / Bun).
import type { HttpClient, HttpRequest } from "../../ports/http.js";
import type { Logger } from "../../ports/logger.js";

export class FetchHttpClient implements HttpClient {
  constructor(private readonly logger: Logger) {}

  async request<T>(
    req: HttpRequest,
    opts: { timeoutMs: number; retries: number; redact: true },
  ): Promise<T> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), opts.timeoutMs);

    let lastError: unknown;
    for (let attempt = 0; attempt <= opts.retries; attempt++) {
      try {
        const res = await fetch(req.url, {
          method: req.method,
          headers: req.headers,
          body: req.body != null ? JSON.stringify(req.body) : undefined,
          signal: controller.signal,
        });

        clearTimeout(timer);

        if (!res.ok) {
          this.logger.error(`HTTP ${req.method} ${req.url} → ${res.status}`, {
            status: res.status,
            redact: opts.redact,
          });
          throw new Error(`HTTP ${res.status}: ${req.url}`);
        }

        const json = await res.json() as T;
        return json;
      } catch (err) {
        lastError = err;
        if (attempt < opts.retries) {
          this.logger.debug(`Retry ${attempt + 1}/${opts.retries} for ${req.url}`, {
            error: String(err),
          });
        }
      }
    }

    clearTimeout(timer);
    throw lastError;
  }
}
