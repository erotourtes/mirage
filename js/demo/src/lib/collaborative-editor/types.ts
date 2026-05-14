import type { DeltaOp, MirageDocument } from "@mirage/wasm";

export type { DeltaOp };

export const TEXT_COLORS = [
  { name: "cyan", value: "#67e8f9" },
  { name: "green", value: "#86efac" },
  { name: "yellow", value: "#fde047" },
  { name: "rose", value: "#fda4af" },
] as const;

export type TextColor = `#${string}`;

export type LoadState = "loading" | "ready" | "error";

export interface TextSelection {
  start: number;
  end: number;
}

export interface CommentRecord {
  id: string;
  authorClientId: number;
  body: string;
}

export interface CommentRange {
  id: string;
  body: string;
  authorClientId: number;
  start: number;
  end: number;
  snippet: string;
}

export interface PendingUpdate {
  targetId: number;
  update: Uint8Array;
}

export type NetworkLogBase = { id: number; time: number };

export type LocalLogEntry = NetworkLogBase & {
  kind: "local";
  clientId: number;
  operation: "insert" | "delete" | "replace" | "format" | "comment";
  start: number;
  end: number;
};

export type EncodedLogEntry = NetworkLogBase & {
  kind: "encoded";
  sourceId: number;
  targetId: number;
  bytes: number;
};

export type QueuedLogEntry = NetworkLogBase & {
  kind: "queued";
  sourceId: number;
  targetId: number;
  bytes: number;
  reason: "source-offline" | "target-offline";
};

export type ScheduledLogEntry = NetworkLogBase & {
  kind: "scheduled";
  sourceId: number;
  targetId: number;
  bytes: number;
  latencyMs: number;
  copy: number;
  copies: number;
};

export type AppliedLogEntry = NetworkLogBase & {
  kind: "applied";
  sourceId: number;
  targetId: number;
  bytes: number;
};

export type FlushLogEntry = NetworkLogBase & {
  kind: "flush";
  sourceId: number;
  targetId: number;
  count: number;
};

export type NetworkLogEntry =
  | LocalLogEntry
  | EncodedLogEntry
  | QueuedLogEntry
  | ScheduledLogEntry
  | AppliedLogEntry
  | FlushLogEntry;

export interface EditorClient {
  id: number;
  name: string;
  doc: MirageDocument;
  connected: boolean;
  latencyMs: number;
  duplicateSend: boolean;
  pendingUpdates: PendingUpdate[];
}
