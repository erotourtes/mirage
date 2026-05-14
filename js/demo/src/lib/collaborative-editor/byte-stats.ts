import type { EditorClient } from "./types";

const encoder = new TextEncoder();

export type ClientByteStats = {
  textLength: number;
  textBytes: number | null;
  fullUpdateBytes: number | null;
  pendingBytes: number;
  internalBytes: number;
};

export type ClientGzipStats = {
  supported: boolean;
  pending: boolean;
  textGzipBytes: number | null;
  fullUpdateGzipBytes: number | null;
};

export function clientByteStats(
  client: EditorClient,
  options: { includeFullUpdate?: boolean; includeTextBytes?: boolean } = {},
): ClientByteStats {
  const includeFullUpdate = options.includeFullUpdate ?? true;
  const includeTextBytes = options.includeTextBytes ?? true;
  const textLength = Number(client.doc.length);
  const textBytes = includeTextBytes ? Number(client.doc.visibleByteLength) : null;
  const fullUpdateBytes = includeFullUpdate
    ? client.doc.encodeUpdate().byteLength
    : null;
  const pendingBytes = client.pendingUpdates.reduce(
    (total, pending) => total + pending.update.byteLength,
    0,
  );

  return {
    textLength,
    textBytes,
    fullUpdateBytes,
    pendingBytes,
    internalBytes: Number(client.doc.internalByteLength),
  };
}

export function emptyGzipStats(options?: {
  pending?: boolean;
}): ClientGzipStats {
  return {
    supported: compressionSupported(),
    pending: options?.pending ?? false,
    textGzipBytes: null,
    fullUpdateGzipBytes: null,
  };
}

export function pendingGzipStats(
  previous?: ClientGzipStats,
): ClientGzipStats {
  if (!previous) return emptyGzipStats({ pending: true });
  return { ...previous, pending: true };
}

export async function clientGzipStats(
  client: EditorClient,
  includeFullUpdate = true,
): Promise<ClientGzipStats> {
  if (!compressionSupported()) {
    return emptyGzipStats();
  }

  const textBytes = encoder.encode(client.doc.toString());
  const fullUpdate = includeFullUpdate ? client.doc.encodeUpdate() : null;
  const [textGzipBytes, fullUpdateGzipBytes] = await Promise.all([
    gzipByteLength(textBytes),
    fullUpdate ? gzipByteLength(fullUpdate) : Promise.resolve(null),
  ]);

  return {
    supported: true,
    pending: false,
    textGzipBytes,
    fullUpdateGzipBytes,
  };
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;

  const kib = bytes / 1024;
  if (kib < 1024) return `${kib.toFixed(1)} KiB`;

  return `${(kib / 1024).toFixed(1)} MiB`;
}

function compressionSupported(): boolean {
  return typeof CompressionStream !== "undefined";
}

async function gzipByteLength(bytes: Uint8Array): Promise<number> {
  const copy = Uint8Array.from(bytes);
  const source = new Blob([copy.buffer]).stream();
  const compressed = source.pipeThrough(new CompressionStream("gzip"));
  return (await new Response(compressed).arrayBuffer()).byteLength;
}
