import { loadMirage } from "$lib/mirage/client";
import type { Mirage } from "@mirage/wasm";
import {
  createSessionSnapshot,
  SharedSessionBridge,
  type SessionSnapshot,
} from "./shared-session";
import type {
  CommentRecord,
  EditorClient,
  NetworkLogEntry,
  PendingUpdate,
  TextColor,
  TextSelection,
} from "./types";

const starterText = `# mirage collaborative editor

- Local-first: each client owns a Mirage document and can edit independently.
- Offline work: disconnect a client, edit locally, then reconnect to sync.
- Performance mode: renders a narrow editor window and pauses expensive full-document stats.
- History: use the slider to inspect previous document revisions.

Example:
the quick brown fox jumps overthe crazy dog`;
const starterBrand = "mirage";
const starterBrandColor = "#67e8f9" satisfies TextColor;
const starterBoldLabels = [
  "Local-first",
  "Offline work",
  "Performance mode",
  "History",
] as const;
const starterTypo = "overthe";
const starterTypoComment = 'Typo: should be "over the".';
const starterCommentId = "c1";
const snapshotPublishDelayMs = 300;

type NetworkLogInput = NetworkLogEntry extends infer Entry
  ? Entry extends NetworkLogEntry
    ? Omit<Entry, "id" | "time">
    : never
  : never;

export class CollaborativeEditorSession {
  readonly comments: CommentRecord[] = [];
  readonly clients: EditorClient[] = [];
  readonly logs: NetworkLogEntry[] = [];

  private nextClientId = 1;
  private nextCommentId = 1;
  private nextLogId = 1;
  private detailedTracking = true;
  private readonly timers: ReturnType<typeof setTimeout>[] = [];
  private snapshotTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly bridge = new SharedSessionBridge(
    (snapshot) => {
      this.applySnapshot(snapshot);
      this.persistSnapshot();
      this.changed();
    },
    (snapshot) => {
      this.clearLocalState();
      this.applySnapshot(snapshot);
      this.persistSnapshot();
      this.changed();
    },
  );

  private constructor(
    private readonly mirage: Mirage,
    private readonly onChange: () => void,
  ) {}

  static async create(
    onChange: () => void,
  ): Promise<CollaborativeEditorSession> {
    const mirage = await loadMirage();
    const session = new CollaborativeEditorSession(mirage, onChange);
    const restored = session.restoreSnapshot();

    if (!restored) {
      const client = session.createClient();
      session.seedStarterDocument(client);
      session.afterLocalChange(client);
    } else {
      session.changed();
    }

    return session;
  }

  destroy(): void {
    this.flushSnapshot();
    this.clearTimers();
    this.destroyDocuments();
    this.bridge.close();
  }

  addClient(sourceId = this.clients[0]?.id): EditorClient {
    const client = this.createClient(sourceId);
    this.fullSync();
    this.publishSnapshot();
    this.changed();
    return client;
  }

  removeClient(clientId: number): EditorClient | null {
    if (this.clients.length <= 1) return null;

    const index = this.clients.findIndex((client) => client.id === clientId);
    if (index === -1) return null;

    const [removed] = this.clients.splice(index, 1);
    removed.doc.destroy();

    for (const client of this.clients) {
      client.pendingUpdates = client.pendingUpdates.filter(
        (pending) => pending.targetId !== clientId,
      );
    }

    this.publishSnapshot();
    this.changed();
    return removed;
  }

  reset(): void {
    this.clearLocalState();
    this.bridge.clear();
    const client = this.createClient();
    this.seedStarterDocument(client);
    const snapshot = this.snapshot();
    this.bridge.persist(snapshot);
    this.bridge.broadcastReset(snapshot);
    this.changed();
  }

  private createClient(sourceId = this.clients[0]?.id): EditorClient {
    const id = this.nextClientId++;
    const doc = this.mirage.createDocument(id);
    const source = this.client(sourceId);

    if (source) {
      doc.applyUpdate(source.doc.encodeUpdate());
    }

    const client: EditorClient = {
      id,
      name: `client-${id}`,
      doc,
      connected: true,
      latencyMs: 0,
      duplicateSend: false,
      pendingUpdates: [],
    };

    this.clients.push(client);
    return client;
  }

  private clearTimers(): void {
    if (this.snapshotTimer) {
      clearTimeout(this.snapshotTimer);
      this.snapshotTimer = null;
    }
    for (const timer of this.timers) {
      clearTimeout(timer);
    }
    this.timers.length = 0;
  }

  private destroyDocuments(): void {
    for (const client of this.clients) {
      client.doc.destroy();
    }
  }

  private clearLocalState(): void {
    this.clearTimers();
    this.destroyDocuments();
    this.comments.length = 0;
    this.clients.length = 0;
    this.logs.length = 0;
    this.nextClientId = 1;
    this.nextCommentId = 1;
    this.nextLogId = 1;
  }

  client(clientId: number | null | undefined): EditorClient | undefined {
    return this.clients.find((client) => client.id === clientId);
  }

  private seedStarterDocument(client: EditorClient): void {
    client.doc.insert(0, starterText);

    const brandStart = starterText.indexOf(starterBrand);
    if (brandStart >= 0) {
      client.doc.format(brandStart, starterBrand.length, {
        key: "color",
        value: starterBrandColor,
      });
    }

    for (const label of starterBoldLabels) {
      const labelStart = starterText.indexOf(label);
      if (labelStart < 0) continue;

      client.doc.format(labelStart, label.length, {
        key: "bold",
        value: "true",
      });
    }

    const typoStart = starterText.indexOf(starterTypo);
    if (typoStart >= 0) {
      this.comments.push({
        id: starterCommentId,
        authorClientId: client.id,
        body: starterTypoComment,
      });
      client.doc.format(typoStart, starterTypo.length, {
        key: "comment",
        value: starterCommentId,
      });
      this.nextCommentId = 2;
    }
  }

  replaceSelection(
    clientId: number,
    selection: TextSelection,
    text: string,
  ): void {
    const client = this.client(clientId);
    if (!client) return;

    const length = selection.end - selection.start;
    const operation =
      length > 0 && text.length > 0
        ? "replace"
        : length > 0
          ? "delete"
          : "insert";
    if (length > 0) {
      client.doc.delete(selection.start, length);
    }
    if (text.length > 0) {
      client.doc.insert(selection.start, text);
    }

    this.addLog({
      kind: "local",
      clientId: client.id,
      operation,
      start: selection.start,
      end: selection.end,
    });
    this.afterLocalChange(client);
  }

  formatBold(clientId: number, selection: TextSelection): void {
    const client = this.client(clientId);
    if (!client || selection.start === selection.end) return;

    client.doc.format(selection.start, selection.end - selection.start, {
      key: "bold",
      value: "true",
    });
    this.addLog({
      kind: "local",
      clientId: client.id,
      operation: "format",
      start: selection.start,
      end: selection.end,
    });
    this.afterLocalChange(client);
  }

  formatColor(
    clientId: number,
    selection: TextSelection,
    color: TextColor,
  ): void {
    const client = this.client(clientId);
    if (!client || selection.start === selection.end) return;

    client.doc.format(selection.start, selection.end - selection.start, {
      key: "color",
      value: color,
    });
    this.addLog({
      kind: "local",
      clientId: client.id,
      operation: "format",
      start: selection.start,
      end: selection.end,
    });
    this.afterLocalChange(client);
  }

  addComment(
    clientId: number,
    selection: TextSelection,
    body = "review this range",
  ): string | null {
    const client = this.client(clientId);
    if (!client || selection.start === selection.end) return null;

    const id = `c${this.nextCommentId++}`;
    this.comments.push({ id, authorClientId: client.id, body });
    client.doc.format(selection.start, selection.end - selection.start, {
      key: "comment",
      value: id,
    });
    this.addLog({
      kind: "local",
      clientId: client.id,
      operation: "comment",
      start: selection.start,
      end: selection.end,
    });
    this.afterLocalChange(client);
    return id;
  }

  setConnected(clientId: number, connected: boolean): void {
    const client = this.client(clientId);
    if (!client) return;

    client.connected = connected;
    if (connected) {
      this.flushPending();
      this.fullSync();
    }
    this.publishSnapshot();
    this.changed();
  }

  setLatency(clientId: number, latencyMs: number): void {
    const client = this.client(clientId);
    if (!client) return;

    client.latencyMs = Math.max(0, Math.min(3000, Math.round(latencyMs)));
    this.publishSnapshot();
    this.changed();
  }

  setDuplicateSend(clientId: number, duplicateSend: boolean): void {
    const client = this.client(clientId);
    if (!client) return;

    client.duplicateSend = duplicateSend;
    this.publishSnapshot();
    this.changed();
  }

  setDetailedTracking(detailedTracking: boolean): void {
    this.detailedTracking = detailedTracking;
    if (!detailedTracking) {
      this.logs.length = 0;
    }
    this.publishSnapshot();
    this.changed();
  }

  private afterLocalChange(source: EditorClient): void {
    this.syncFrom(source);
    this.publishSnapshot();
    this.changed();
  }

  private fullSync(): void {
    for (const source of this.clients) {
      if (!source.connected) continue;
      this.syncFrom(source);
    }
  }

  private syncFrom(source: EditorClient): void {
    for (const target of this.clients) {
      if (target.id === source.id) continue;

      const update = source.doc.encodeUpdate(target.doc.encodeStateVector());
      if (update.byteLength === 0) continue;
      this.addLog({
        kind: "encoded",
        sourceId: source.id,
        targetId: target.id,
        bytes: update.byteLength,
      });
      this.queueOrDeliver(source, target, update);
    }
  }

  private queueOrDeliver(
    source: EditorClient,
    target: EditorClient,
    update: Uint8Array,
  ): void {
    if (!source.connected || !target.connected) {
      this.queuePendingUpdate(source, target, update);
      this.addLog({
        kind: "queued",
        sourceId: source.id,
        targetId: target.id,
        bytes: update.byteLength,
        reason: source.connected ? "target-offline" : "source-offline",
      });
      this.changed();
      return;
    }

    this.scheduleDelivery(source, target, update);
  }

  private scheduleDelivery(
    source: EditorClient,
    target: EditorClient,
    update: Uint8Array,
  ): void {
    const copies = source.duplicateSend ? 2 : 1;

    for (let copy = 0; copy < copies; copy += 1) {
      this.addLog({
        kind: "scheduled",
        sourceId: source.id,
        targetId: target.id,
        bytes: update.byteLength,
        latencyMs: source.latencyMs,
        copy: copy + 1,
        copies,
      });

      const timer = setTimeout(() => {
        if (!source.connected || !target.connected) {
          this.queuePendingUpdate(source, target, update);
          this.addLog({
            kind: "queued",
            sourceId: source.id,
            targetId: target.id,
            bytes: update.byteLength,
            reason: source.connected ? "target-offline" : "source-offline",
          });
          this.publishSnapshot();
          this.changed();
          return;
        }

        target.doc.applyUpdate(update);
        this.addLog({
          kind: "applied",
          sourceId: source.id,
          targetId: target.id,
          bytes: update.byteLength,
        });
        this.publishSnapshot();
        this.changed();
      }, source.latencyMs);

      this.timers.push(timer);
    }
  }

  private queuePendingUpdate(
    source: EditorClient,
    target: EditorClient,
    update: Uint8Array,
  ): void {
    const existing = source.pendingUpdates.find(
      (pending) => pending.targetId === target.id,
    );

    if (existing) {
      existing.update = update.slice();
      return;
    }

    source.pendingUpdates.push({ targetId: target.id, update: update.slice() });
  }

  private flushPending(): void {
    for (const source of this.clients) {
      const remaining: PendingUpdate[] = [];

      for (const pending of source.pendingUpdates) {
        const target = this.client(pending.targetId);
        if (!target || !source.connected || !target.connected) {
          remaining.push(pending);
          continue;
        }

        this.addLog({
          kind: "flush",
          sourceId: source.id,
          targetId: target.id,
          count: 1,
        });
      }

      source.pendingUpdates = remaining;
    }
  }

  private changed(): void {
    this.onChange();
  }

  private addLog(entry: NetworkLogInput): void {
    if (!this.detailedTracking) return;

    this.logs.unshift({ ...entry, id: this.nextLogId++, time: Date.now() });

    this.logs.splice(200);
  }

  private snapshot(): SessionSnapshot {
    return createSessionSnapshot(
      this.comments,
      this.clients,
      this.logs,
      this.nextClientId,
      this.nextCommentId,
      this.nextLogId,
    );
  }

  private restoreSnapshot(): boolean {
    const snapshot = this.bridge.restore();
    if (!snapshot) return false;

    this.applySnapshot(snapshot);
    return this.clients.length > 0;
  }

  private applySnapshot(snapshot: SessionSnapshot): void {
    const nextClientId = snapshot.nextClientId ?? 1;
    const nextCommentId = snapshot.nextCommentId ?? 1;
    const nextLogId = snapshot.nextLogId ?? 1;

    this.nextClientId = Math.max(this.nextClientId, nextClientId);
    this.nextCommentId = Math.max(this.nextCommentId, nextCommentId);
    this.nextLogId = Math.max(this.nextLogId, nextLogId);

    this.comments.length = 0;
    this.comments.push(
      ...(snapshot.comments ?? []).map((comment) => ({ ...comment })),
    );

    const remoteClientIds = new Set(
      snapshot.clients.map((remoteClient) => remoteClient.id),
    );

    for (let index = this.clients.length - 1; index >= 0; index -= 1) {
      const client = this.clients[index];
      if (remoteClientIds.has(client.id)) continue;

      client.doc.destroy();
      this.clients.splice(index, 1);
    }

    for (const remoteClient of snapshot.clients) {
      let client = this.client(remoteClient.id);

      if (!client) {
        client = {
          id: remoteClient.id,
          name: remoteClient.name,
          doc: this.mirage.createDocument(remoteClient.id),
          connected: remoteClient.connected,
          latencyMs: remoteClient.latencyMs,
          duplicateSend: remoteClient.duplicateSend,
          pendingUpdates: [],
        };
        this.clients.push(client);
      }

      client.name = remoteClient.name;
      client.connected = remoteClient.connected;
      client.latencyMs = remoteClient.latencyMs;
      client.duplicateSend = remoteClient.duplicateSend;
      client.pendingUpdates = (remoteClient.pendingUpdates ?? []).map(
        (pending) => ({
          targetId: pending.targetId,
          update: new Uint8Array(pending.update),
        }),
      );
      client.doc.applyUpdate(new Uint8Array(remoteClient.update));
    }

    const maxClientId = Math.max(0, ...this.clients.map((client) => client.id));
    this.nextClientId = Math.max(this.nextClientId, maxClientId + 1);

    const seenLogIds = new Set(this.logs.map((log) => log.id));
    for (const log of snapshot.logs ?? []) {
      if (!seenLogIds.has(log.id)) {
        this.logs.push({ ...log });
        seenLogIds.add(log.id);
      }
    }
    this.logs.sort(
      (left, right) => right.time - left.time || right.id - left.id,
    );
    this.logs.splice(200);
  }

  private persistSnapshot(): void {
    this.bridge.persist(this.snapshot());
  }

  private broadcastSnapshot(): void {
    this.bridge.broadcastSnapshot(this.snapshot());
  }

  private publishSnapshot(): void {
    if (this.snapshotTimer) {
      clearTimeout(this.snapshotTimer);
    }

    this.snapshotTimer = setTimeout(() => {
      this.snapshotTimer = null;
      const snapshot = this.snapshot();
      this.bridge.persist(snapshot);
      this.bridge.broadcastSnapshot(snapshot);
    }, snapshotPublishDelayMs);
  }

  private flushSnapshot(): void {
    if (!this.snapshotTimer) return;

    clearTimeout(this.snapshotTimer);
    this.snapshotTimer = null;
    const snapshot = this.snapshot();
    this.bridge.persist(snapshot);
    this.bridge.broadcastSnapshot(snapshot);
  }
}
