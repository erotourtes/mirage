import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CollaborativeEditorSession } from "./session";

vi.mock("$lib/mirage/client", async () => {
  const { instantiateMirage } = await import("@mirage/wasm");
  const { readFile } = await import("node:fs/promises");
  const { resolve } = await import("node:path");

  let miragePromise: ReturnType<typeof instantiateMirage> | null = null;

  return {
    loadMirage() {
      miragePromise ??= readFile(
        resolve(process.cwd(), "../../mirage_zig/zig-out/wasm/mirage.wasm"),
      ).then((bytes) => instantiateMirage(bytes));
      return miragePromise;
    },
  };
});

let session: CollaborativeEditorSession | null = null;
let changeCount = 0;

function createLocalStorage(): Storage {
  const values = new Map<string, string>();

  return {
    get length() {
      return values.size;
    },
    clear() {
      values.clear();
    },
    getItem(key: string) {
      return values.get(key) ?? null;
    },
    key(index: number) {
      return [...values.keys()][index] ?? null;
    },
    removeItem(key: string) {
      values.delete(key);
    },
    setItem(key: string, value: string) {
      values.set(key, value);
    },
  };
}

async function createSession() {
  session = await CollaborativeEditorSession.create(() => {
    changeCount += 1;
  });
  return session;
}

async function deliverTimers() {
  await vi.runAllTimersAsync();
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.stubGlobal("localStorage", createLocalStorage());
  changeCount = 0;
});

afterEach(() => {
  session?.destroy();
  session = null;
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("CollaborativeEditorSession", () => {
  it("creates one connected client with starter text", async () => {
    const created = await createSession();

    expect(created.clients).toHaveLength(1);
    expect(created.clients[0]?.name).toBe("client-1");
    expect(created.clients[0]?.connected).toBe(true);
    expect(created.clients[0]?.doc.toString()).toContain(
      "# mirage collaborative editor",
    );
    expect(created.clients[0]?.doc.toString()).toContain(
      "the quick brown fox jumps overthe crazy dog",
    );
    expect(created.clients[0]?.doc.toString()).not.toContain("**");
    expect(created.comments).toEqual([
      {
        id: "c1",
        authorClientId: created.clients[0]?.id,
        body: 'Typo: should be "over the".',
      },
    ]);
    expect(
      created.clients[0]?.doc
        .toDelta()
        .find((op) => op.insert.includes("mirage"))?.attributes?.color,
    ).toBe("#67e8f9");
    expect(
      created.clients[0]?.doc
        .toDelta()
        .find((op) => op.insert.includes("Performance mode"))?.attributes
        ?.bold,
    ).toBe("true");
    expect(
      created.clients[0]?.doc
        .toDelta()
        .find((op) => op.insert.includes("overthe"))?.attributes?.comment,
    ).toBe("c1");
    expect(changeCount).toBeGreaterThan(0);
  });

  it("adds a client from the active document state", async () => {
    const created = await createSession();
    const client1 = created.clients[0];
    expect(client1).toBeDefined();

    created.formatColor(client1.id, { start: 0, end: 6 }, "#123456");
    const client2 = created.addClient(client1.id);

    expect(created.clients).toHaveLength(2);
    expect(client2.doc.toString()).toBe(client1.doc.toString());
    expect(client2.doc.toDelta()[0]?.attributes?.color).toBe("#123456");
  });

  it("syncs text edits between connected clients", async () => {
    const created = await createSession();
    const client1 = created.clients[0];
    expect(client1).toBeDefined();
    const client2 = created.addClient(client1.id);

    created.replaceSelection(client1.id, { start: 0, end: 6 }, "Mirror");
    await deliverTimers();

    expect(client1.doc.toString()).toBe(client2.doc.toString());
    expect(client2.doc.toString().startsWith("Mirror")).toBe(true);
  });

  it("queues updates while a target client is disconnected and flushes on reconnect", async () => {
    const created = await createSession();
    const client1 = created.clients[0];
    expect(client1).toBeDefined();
    const client2 = created.addClient(client1.id);

    created.setConnected(client2.id, false);
    created.replaceSelection(client1.id, { start: 0, end: 6 }, "Offline");
    await deliverTimers();

    expect(client2.doc.toString().startsWith("# mirage")).toBe(true);
    expect(client1.pendingUpdates.length).toBeGreaterThan(0);

    created.setConnected(client2.id, true);
    await deliverTimers();

    expect(client1.pendingUpdates).toHaveLength(0);
    expect(client2.doc.toString().startsWith("Offline")).toBe(true);
  });

  it("coalesces offline edits into one catch-up update on reconnect", async () => {
    const created = await createSession();
    const client1 = created.clients[0];
    expect(client1).toBeDefined();
    const client2 = created.addClient(client1.id);

    created.setConnected(client2.id, false);
    created.replaceSelection(client1.id, { start: 0, end: 0 }, "a");
    created.replaceSelection(client1.id, { start: 1, end: 1 }, "b");
    created.replaceSelection(client1.id, { start: 2, end: 2 }, "c");
    await deliverTimers();

    expect(client1.pendingUpdates).toHaveLength(1);
    expect(client2.doc.toString().startsWith("# mirage")).toBe(true);

    const appliedBefore = created.logs.filter(
      (log) =>
        log.kind === "applied" &&
        log.sourceId === client1.id &&
        log.targetId === client2.id,
    ).length;

    created.setConnected(client2.id, true);
    await deliverTimers();

    const appliedAfter = created.logs.filter(
      (log) =>
        log.kind === "applied" &&
        log.sourceId === client1.id &&
        log.targetId === client2.id,
    ).length;

    expect(client1.pendingUpdates).toHaveLength(0);
    expect(client2.doc.toString().startsWith("abc# mirage")).toBe(true);
    expect(appliedAfter - appliedBefore).toBe(1);
  });

  it("syncs bold, color, and comment attributes", async () => {
    const created = await createSession();
    const client1 = created.clients[0];
    expect(client1).toBeDefined();
    const client2 = created.addClient(client1.id);

    created.formatBold(client1.id, { start: 0, end: 6 });
    created.formatColor(client1.id, { start: 0, end: 6 }, "#86efac");
    const commentId = created.addComment(
      client1.id,
      { start: 0, end: 6 },
      "review name",
    );
    await deliverTimers();

    expect(commentId).toBe("c2");
    expect(created.comments).toEqual(
      expect.arrayContaining([
        { id: "c2", authorClientId: client1.id, body: "review name" },
      ]),
    );
    expect(client2.doc.toDelta()[0]?.attributes).toMatchObject({
      bold: "true",
      color: "#86efac",
      comment: "c2",
    });
  });

  it("updates demo network settings", async () => {
    const created = await createSession();
    const client = created.clients[0];
    expect(client).toBeDefined();

    created.setLatency(client.id, 3150);
    created.setDuplicateSend(client.id, true);
    created.setConnected(client.id, false);

    expect(client.latencyMs).toBe(3000);
    expect(client.duplicateSend).toBe(true);
    expect(client.connected).toBe(false);
  });

  it("removes a client and drops queued updates targeting it", async () => {
    const created = await createSession();
    const client1 = created.clients[0];
    expect(client1).toBeDefined();
    const client2 = created.addClient(client1.id);

    created.setConnected(client2.id, false);
    created.replaceSelection(client1.id, { start: 0, end: 6 }, "Offline");
    await deliverTimers();

    expect(client1.pendingUpdates.length).toBeGreaterThan(0);

    const removed = created.removeClient(client2.id);

    expect(removed?.id).toBe(client2.id);
    expect(created.clients.map((client) => client.id)).toEqual([client1.id]);
    expect(client1.pendingUpdates).toHaveLength(0);
    expect(created.removeClient(client1.id)).toBeNull();
  });

  it("resets the session to a fresh starter client", async () => {
    const created = await createSession();
    const client1 = created.clients[0];
    expect(client1).toBeDefined();
    const client2 = created.addClient(client1.id);

    created.replaceSelection(client1.id, { start: 0, end: 6 }, "Edited");
    created.addComment(client2.id, { start: 0, end: 6 }, "reset me");
    await deliverTimers();

    expect(created.logs.length).toBeGreaterThan(0);

    created.reset();

    expect(created.clients).toHaveLength(1);
    expect(created.clients[0]?.id).toBe(1);
    expect(created.clients[0]?.doc.toString()).toContain(
      "# mirage collaborative editor",
    );
    expect(created.comments).toEqual([
      {
        id: "c1",
        authorClientId: created.clients[0]?.id,
        body: 'Typo: should be "over the".',
      },
    ]);
    expect(created.logs).toHaveLength(0);
  });

  it("records local and network log entries", async () => {
    const created = await createSession();
    const client1 = created.clients[0];
    expect(client1).toBeDefined();
    const client2 = created.addClient(client1.id);

    created.replaceSelection(client1.id, { start: 0, end: 6 }, "Logged");

    expect(created.logs.map((log) => log.kind)).toEqual(
      expect.arrayContaining(["local", "encoded", "scheduled"]),
    );

    await deliverTimers();

    expect(created.logs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          kind: "applied",
          sourceId: client1.id,
          targetId: client2.id,
        }),
      ]),
    );
  });

  it("restores persisted clients, updates, and comments for a later tab", async () => {
    const first = await createSession();
    const client1 = first.clients[0];
    expect(client1).toBeDefined();

    const client2 = first.addClient(client1.id);
    first.formatColor(client1.id, { start: 0, end: 6 }, "#123456");
    const commentId = first.addComment(client2.id, { start: 0, end: 6 }, "tab");
    await deliverTimers();

    first.destroy();
    session = null;
    changeCount = 0;

    const restored = await createSession();

    expect(restored.clients).toHaveLength(2);
    expect(restored.clients[0]?.doc.toDelta()[0]?.attributes?.color).toBe(
      "#123456",
    );
    expect(restored.comments).toEqual(
      expect.arrayContaining([
        {
          id: "c1",
          authorClientId: client1.id,
          body: 'Typo: should be "over the".',
        },
        { id: commentId, authorClientId: client2.id, body: "tab" },
      ]),
    );
    expect(restored.logs.length).toBeGreaterThan(0);
  });
});
