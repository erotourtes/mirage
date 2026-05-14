import type { CommentRecord, EditorClient, NetworkLogEntry } from "./types";

const sharedStorageKey = "mirage:collaborative-editor:v1";
const sharedChannelName = "mirage-collaborative-editor";

export type ClientSnapshot = {
  id: number;
  name: string;
  connected: boolean;
  latencyMs: number;
  duplicateSend: boolean;
  pendingUpdates: PendingUpdateSnapshot[];
  update: number[];
};

export type PendingUpdateSnapshot = { targetId: number; update: number[] };

export type SessionSnapshot = {
  comments: CommentRecord[];
  clients: ClientSnapshot[];
  logs: NetworkLogEntry[];
  nextClientId: number;
  nextCommentId: number;
  nextLogId: number;
};

type SharedMessage =
  | { sourceId: string; type: "snapshot"; snapshot: SessionSnapshot }
  | { sourceId: string; type: "reset"; snapshot: SessionSnapshot };

export function createSessionSnapshot(
  comments: CommentRecord[],
  clients: EditorClient[],
  logs: NetworkLogEntry[],
  nextClientId: number,
  nextCommentId: number,
  nextLogId: number,
): SessionSnapshot {
  return {
    comments: comments.map((comment) => ({ ...comment })),
    clients: clients.map((client) => ({
      id: client.id,
      name: client.name,
      connected: client.connected,
      latencyMs: client.latencyMs,
      duplicateSend: client.duplicateSend,
      pendingUpdates: client.pendingUpdates.map((pending) => ({
        targetId: pending.targetId,
        update: [...pending.update],
      })),
      update: [...client.doc.encodeUpdate()],
    })),
    logs: logs.map((log) => ({ ...log })),
    nextClientId,
    nextCommentId,
    nextLogId,
  };
}

export class SharedSessionBridge {
  private readonly sourceId = crypto.randomUUID();
  private readonly channel =
    typeof BroadcastChannel === "undefined"
      ? null
      : new BroadcastChannel(sharedChannelName);

  constructor(
    private readonly onSnapshot: (snapshot: SessionSnapshot) => void,
    private readonly onReset: (snapshot: SessionSnapshot) => void,
  ) {
    this.channel?.addEventListener("message", (event: MessageEvent) => {
      const message = event.data as Partial<SharedMessage>;
      if (message.sourceId === this.sourceId || !message.snapshot) return;

      if (message.type === "reset") {
        this.onReset(message.snapshot);
      } else if (message.type === "snapshot") {
        this.onSnapshot(message.snapshot);
      }
    });
  }

  close(): void {
    this.channel?.close();
  }

  restore(): SessionSnapshot | null {
    if (typeof localStorage === "undefined") return null;

    const value = localStorage.getItem(sharedStorageKey);
    if (!value) return null;

    try {
      return JSON.parse(value) as SessionSnapshot;
    } catch {
      localStorage.removeItem(sharedStorageKey);
      return null;
    }
  }

  persist(snapshot: SessionSnapshot): void {
    if (typeof localStorage !== "undefined") {
      localStorage.setItem(sharedStorageKey, JSON.stringify(snapshot));
    }
  }

  clear(): void {
    if (typeof localStorage !== "undefined") {
      localStorage.removeItem(sharedStorageKey);
    }
  }

  broadcastSnapshot(snapshot: SessionSnapshot): void {
    this.channel?.postMessage({
      sourceId: this.sourceId,
      type: "snapshot",
      snapshot,
    } satisfies SharedMessage);
  }

  broadcastReset(snapshot: SessionSnapshot): void {
    this.channel?.postMessage({
      sourceId: this.sourceId,
      type: "reset",
      snapshot,
    } satisfies SharedMessage);
  }
}
