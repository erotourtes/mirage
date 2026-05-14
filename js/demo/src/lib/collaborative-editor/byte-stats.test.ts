import { describe, expect, it } from "vitest";
import { clientByteStats, formatBytes, pendingGzipStats } from "./byte-stats";
import type { EditorClient } from "./types";

function clientWithSizes(): EditorClient {
  return {
    id: 1,
    name: "client-1",
    connected: true,
    latencyMs: 0,
    duplicateSend: false,
    pendingUpdates: [
      { targetId: 2, update: new Uint8Array([1, 2, 3]) },
      { targetId: 3, update: new Uint8Array([4, 5]) },
    ],
    doc: {
      handle: 1,
      length: 5n,
      currentRevision: 1n,
      historyLength: 1n,
      internalByteLength: 1234n,
      visibleByteLength: 5n,
      insert: () => {},
      format: () => {},
      delete: () => {},
      compact: () => {},
      visibleByteLengthAt: () => 5n,
      toString: () => "hello",
      toDelta: () => [{ insert: "hello" }],
      toDeltaRange: () => [{ insert: "hello" }],
      encodeStateVector: () => new Uint8Array(),
      encodeUpdate: () => new Uint8Array([1, 2, 3, 4]),
      applyUpdate: () => {},
      destroy: () => {},
    },
  };
}

describe("formatBytes", () => {
  it("formats bytes", () => {
    expect(formatBytes(0)).toBe("0 B");
    expect(formatBytes(512)).toBe("512 B");
  });

  it("formats kibibytes", () => {
    expect(formatBytes(1536)).toBe("1.5 KiB");
  });

  it("formats mebibytes", () => {
    expect(formatBytes(2 * 1024 * 1024)).toBe("2.0 MiB");
  });
});

describe("clientByteStats", () => {
  it("uses the Mirage internal byte length instead of a frontend estimate", () => {
    expect(clientByteStats(clientWithSizes())).toEqual({
      textLength: 5,
      textBytes: 5,
      fullUpdateBytes: 4,
      pendingBytes: 5,
      internalBytes: 1234,
    });
  });

  it("can skip expensive full update encoding", () => {
    expect(
      clientByteStats(clientWithSizes(), { includeFullUpdate: false })
        .fullUpdateBytes,
    ).toBeNull();
  });

  it("can pause exact visible byte calculation", () => {
    expect(
      clientByteStats(clientWithSizes(), { includeTextBytes: false }).textBytes,
    ).toBeNull();
  });
});

describe("pendingGzipStats", () => {
  it("keeps the last measured gzip sizes while a refresh is pending", () => {
    expect(
      pendingGzipStats({
        supported: true,
        pending: false,
        textGzipBytes: 12,
        fullUpdateGzipBytes: 34,
      }),
    ).toEqual({
      supported: true,
      pending: true,
      textGzipBytes: 12,
      fullUpdateGzipBytes: 34,
    });
  });
});
