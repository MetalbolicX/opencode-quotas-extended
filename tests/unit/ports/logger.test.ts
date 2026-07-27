import { describe, expect, it } from "vitest";
import type { Logger } from "../../../src/ports/logger.js";

describe("Logger port", () => {
  describe("noopLogger", () => {
    it("is exported from the logger port", async () => {
      const { noopLogger } = await import("../../../src/ports/logger.js");
      expect(noopLogger).toBeDefined();
    });

    it("satisfies the Logger interface", async () => {
      const { noopLogger } = await import("../../../src/ports/logger.js");
      const logger: Logger = noopLogger;
      expect(typeof logger.debug).toBe("function");
      expect(typeof logger.info).toBe("function");
      expect(typeof logger.warn).toBe("function");
      expect(typeof logger.error).toBe("function");
    });

    it("all methods are no-ops (return undefined)", async () => {
      const { noopLogger } = await import("../../../src/ports/logger.js");
      expect(noopLogger.debug("event")).toBeUndefined();
      expect(noopLogger.info("event")).toBeUndefined();
      expect(noopLogger.warn("event")).toBeUndefined();
      expect(noopLogger.error("event")).toBeUndefined();
    });

    it("methods accept optional meta parameter without throwing", async () => {
      const { noopLogger } = await import("../../../src/ports/logger.js");
      expect(noopLogger.debug("event", { key: "value" })).toBeUndefined();
      expect(noopLogger.info("event", { key: "value" })).toBeUndefined();
      expect(noopLogger.warn("event", { key: "value" })).toBeUndefined();
      expect(noopLogger.error("event", { key: "value" })).toBeUndefined();
    });
  });
});
