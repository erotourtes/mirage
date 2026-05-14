<script lang="ts">
  import { resolve } from "$app/paths";
  import { onMount } from "svelte";
  import {
    clientByteStats,
    clientGzipStats,
    emptyGzipStats,
    pendingGzipStats,
    type ClientGzipStats,
  } from "$lib/collaborative-editor/byte-stats";
  import ClientBar from "$lib/collaborative-editor/ClientBar.svelte";
  import ClientPane from "$lib/collaborative-editor/ClientPane.svelte";
  import HistoryModal from "$lib/collaborative-editor/HistoryModal.svelte";
  import RightInspector from "$lib/collaborative-editor/RightInspector.svelte";
  import {
    clampSelectionToLength,
    commentsFromDelta,
  } from "$lib/collaborative-editor/delta";
  import { CollaborativeEditorSession } from "$lib/collaborative-editor/session";
  import type {
    LoadState,
    TextColor,
    TextSelection,
  } from "$lib/collaborative-editor/types";

  const GZIP_STATS_DEBOUNCE_MS = 120;

  let loadState = $state<LoadState>("loading");
  let errorMessage = $state("");
  let session = $state<CollaborativeEditorSession | null>(null);
  let activeClientId = $state<number | null>(null);
  let selectedCommentId = $state<string | null>(null);
  let selections = $state<Record<number, TextSelection>>({});
  let selectionVersions = $state<Record<number, number>>({});
  let version = $state(0);
  let historyOpen = $state(false);
  let historyRevision = $state(0);
  let compareClients = $state(false);
  let performanceMode = $state(false);
  let activeGzipStats = $state<ClientGzipStats>(emptyGzipStats());
  let cachedGzipStats = emptyGzipStats();
  let cachedGzipClientId: number | null = null;

  let activeClient = $derived.by(() => {
    track(version);
    const client = session?.client(activeClientId) ?? session?.clients[0];
    return client
      ? { ...client, pendingUpdates: [...client.pendingUpdates] }
      : null;
  });
  let activeDelta = $derived.by(() => {
    track(version);
    if (performanceMode) return [];
    return activeClient?.doc.toDelta() ?? [];
  });
  let clients = $derived.by(() => {
    track(version);
    return (session?.clients ?? []).map((client) => ({
      ...client,
      pendingUpdates: [...client.pendingUpdates],
    }));
  });
  let commentRanges = $derived.by(() => {
    track(version);
    return commentsFromDelta(activeDelta, session?.comments ?? []);
  });
  let visibleClients = $derived.by(() => {
    track(version);
    if (compareClients) return clients;

    const selected =
      clients.find((client) => client.id === activeClient?.id) ?? clients[0];
    return selected ? [selected] : [];
  });
  let activeByteStats = $derived.by(() => {
    track(version);
    return activeClient
      ? clientByteStats(activeClient, {
          includeFullUpdate: !performanceMode,
          includeTextBytes: !performanceMode,
        })
      : null;
  });
  let networkLogs = $derived.by(() => {
    track(version);
    return [...(session?.logs ?? [])];
  });
  let maxHistoryRevision = $derived(
    activeClient ? Number(activeClient.doc.currentRevision) : 0,
  );
  let historyDelta = $derived.by(() => {
    track(version);
    if (!activeClient) return [];
    const revision = Math.max(0, Math.min(historyRevision, maxHistoryRevision));
    return activeClient.doc.toDelta(revision);
  });

  function track(_value: unknown): void {}

  function setActiveGzipStats(next: ClientGzipStats): void {
    cachedGzipStats = next;
    activeGzipStats = next;
  }

  function resetActiveGzipStats(): void {
    cachedGzipClientId = null;
    setActiveGzipStats(emptyGzipStats());
  }

  function emptySelection(): TextSelection {
    return { start: 0, end: 0 };
  }

  function selectionFor(clientId: number): TextSelection {
    return selections[clientId] ?? emptySelection();
  }

  function selectionVersionFor(clientId: number): number {
    return selectionVersions[clientId] ?? 0;
  }

  onMount(() => {
    let disposed = false;

    async function start() {
      try {
        const created = await CollaborativeEditorSession.create(() => {
          version += 1;
        });

        if (disposed) {
          created.destroy();
          return;
        }

        session = created;
        activeClientId = created.clients[0]?.id ?? null;
        loadState = "ready";
      } catch (error) {
        errorMessage = error instanceof Error ? error.message : String(error);
        loadState = "error";
      }
    }

    void start();

    return () => {
      disposed = true;
      session?.destroy();
    };
  });

  $effect(() => {
    const client = activeClient;
    const includeFullUpdate = !performanceMode;
    const revision = client?.doc.currentRevision.toString() ?? "none";
    track(revision);

    if (!client) {
      resetActiveGzipStats();
      return;
    }

    if (!includeFullUpdate) {
      resetActiveGzipStats();
      return;
    }

    let cancelled = false;
    const previous =
      cachedGzipClientId === client.id ? cachedGzipStats : undefined;
    cachedGzipClientId = client.id;
    setActiveGzipStats(pendingGzipStats(previous));

    const timer = setTimeout(() => {
      void clientGzipStats(client, includeFullUpdate).then((next) => {
        if (!cancelled) setActiveGzipStats(next);
      });
    }, GZIP_STATS_DEBOUNCE_MS);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  });

  function focusClient(clientId: number) {
    activeClientId = clientId;
  }

  function setSelection(clientId: number, next: TextSelection) {
    selections = { ...selections, [clientId]: next };
    selectionVersions = {
      ...selectionVersions,
      [clientId]: selectionVersionFor(clientId) + 1,
    };
    focusClient(clientId);
  }

  function replaceRange(clientId: number, range: TextSelection, text: string) {
    const client = session?.client(clientId);
    if (!session || !client) return;

    const safeRange = clampSelectionToLength(
      range.start,
      range.end,
      Number(client.doc.length),
    );
    session.replaceSelection(client.id, safeRange, text);
    const cursor = safeRange.start + [...text].length;
    setSelection(client.id, { start: cursor, end: cursor });
  }

  function formatBold(clientId: number) {
    const client = session?.client(clientId);
    if (!session || !client) return;

    const selection = selectionFor(client.id);
    const safeRange = clampSelectionToLength(
      selection.start,
      selection.end,
      Number(client.doc.length),
    );
    session.formatBold(client.id, safeRange);
    setSelection(client.id, safeRange);
  }

  function formatColor(clientId: number, color: TextColor) {
    const client = session?.client(clientId);
    if (!session || !client) return;

    const selection = selectionFor(client.id);
    const safeRange = clampSelectionToLength(
      selection.start,
      selection.end,
      Number(client.doc.length),
    );
    session.formatColor(client.id, safeRange, color);
    setSelection(client.id, safeRange);
  }

  function addComment(clientId: number) {
    const client = session?.client(clientId);
    if (!session || !client) return;

    const selection = selectionFor(client.id);
    const safeRange = clampSelectionToLength(
      selection.start,
      selection.end,
      Number(client.doc.length),
    );
    if (safeRange.start === safeRange.end) return;

    const body = window.prompt("comment", "review this range");
    if (body === null) return;

    const id = session.addComment(
      client.id,
      safeRange,
      body.trim() || "comment",
    );
    selectedCommentId = id;
    setSelection(client.id, safeRange);
  }

  function addClient() {
    if (!session) return;
    const client = session.addClient(activeClientId ?? undefined);
    activeClientId = client.id;
    selectedCommentId = null;
    setSelection(client.id, emptySelection());
  }

  function removeClient(clientId: number) {
    if (!session) return;

    const removed = session.removeClient(clientId);
    if (!removed) return;

    if (activeClientId === clientId) {
      activeClientId = session.clients[0]?.id ?? null;
      selectedCommentId = null;
    }

    const { [clientId]: _selection, ...nextSelections } = selections;
    const { [clientId]: _version, ...nextSelectionVersions } =
      selectionVersions;
    selections = nextSelections;
    selectionVersions = nextSelectionVersions;
  }

  function resetSession() {
    if (!session) return;

    session.reset();
    activeClientId = session.clients[0]?.id ?? null;
    selectedCommentId = null;
    selections = {};
    selectionVersions = {};
    compareClients = false;
    historyOpen = false;
    historyRevision = 0;
  }

  function setCompareClients(nextCompareClients: boolean) {
    compareClients = nextCompareClients;
  }

  function setPerformanceMode(nextPerformanceMode: boolean) {
    performanceMode = nextPerformanceMode;
    session?.setDetailedTracking(!nextPerformanceMode);
    selectedCommentId = null;
  }

  function openHistory(clientId: number) {
    const client = session?.client(clientId);
    if (!client) return;
    activeClientId = client.id;
    historyRevision = Number(client.doc.currentRevision);
    historyOpen = true;
  }

  function selectClient(clientId: number) {
    activeClientId = clientId;
    selectedCommentId = null;
    setSelection(clientId, emptySelection());
  }

  function setClientConnected(clientId: number, connected: boolean) {
    if (session) {
      session.setConnected(clientId, connected);
    }
  }

  function setClientDuplicateSend(clientId: number, duplicateSend: boolean) {
    if (session) {
      session.setDuplicateSend(clientId, duplicateSend);
    }
  }

  function setClientLatency(clientId: number, latencyMs: number) {
    if (session) {
      session.setLatency(clientId, latencyMs);
    }
  }

  function updateSelection(clientId: number, next: TextSelection) {
    selections = { ...selections, [clientId]: next };
    focusClient(clientId);
  }

  function selectComment(commentId: string | null) {
    selectedCommentId = commentId;
  }

  function closeHistory() {
    historyOpen = false;
  }

  function setHistoryRevision(revision: number) {
    historyRevision = revision;
  }
</script>

<svelte:head>
  <title>Collaborative Editor | Mirage</title>
  <meta
    name="description"
    content="Local-first collaborative editor demo powered by Mirage."
  />
</svelte:head>

<main class="h-svh overflow-hidden bg-neutral-950 font-mono text-neutral-100">
  <section class="mx-auto flex h-full w-full max-w-7xl flex-col px-4 py-4">
    <header
      class="flex items-center justify-between border border-neutral-700 bg-neutral-950 px-3 py-2"
    >
      <a class="text-sm font-bold text-cyan-300" href={resolve("/")}>mirage</a>
      <div class="text-xs text-neutral-500">/collaborative-editor</div>
    </header>

    {#if loadState === "loading"}
      <div class="mt-3 border border-neutral-700 p-4 text-sm text-neutral-400">
        loading wasm editor core...
      </div>
    {:else if loadState === "error"}
      <div
        class="mt-3 border border-red-700 bg-red-950 p-4 text-sm text-red-100"
      >
        {errorMessage}
      </div>
    {:else}
      <div
        class="mt-3 grid min-h-0 flex-1 gap-3 lg:grid-cols-[15rem_minmax(0,1fr)_18rem]"
      >
        <div class="channel-scrollbar min-h-0 overflow-auto">
          <ClientBar
            {clients}
            {activeClientId}
            {compareClients}
            {performanceMode}
            onAddClient={addClient}
            onCompareChange={setCompareClients}
            onPerformanceModeChange={setPerformanceMode}
            onRemoveClient={removeClient}
            onReset={resetSession}
            onSelect={selectClient}
          />
        </div>

        <div class="channel-scrollbar min-h-0 overflow-auto">
          <div
            class={`grid min-h-full gap-3 ${
              compareClients
                ? "auto-rows-[minmax(28rem,44rem)] xl:grid-cols-2"
                : "h-full"
            }`}
          >
            {#each visibleClients as client (client.id)}
              <ClientPane
                {client}
                active={client.id === activeClientId}
                {performanceMode}
                {selectedCommentId}
                selection={selectionFor(client.id)}
                selectionVersion={selectionVersionFor(client.id)}
                onBold={() => formatBold(client.id)}
                onColor={(color: TextColor) => formatColor(client.id, color)}
                onComment={() => addComment(client.id)}
                onConnectedChange={(connected: boolean) =>
                  setClientConnected(client.id, connected)}
                onDuplicateChange={(duplicateSend: boolean) =>
                  setClientDuplicateSend(client.id, duplicateSend)}
                onFocus={() => focusClient(client.id)}
                onHistory={() => openHistory(client.id)}
                onLatencyChange={(latencyMs: number) =>
                  setClientLatency(client.id, latencyMs)}
                onReplace={(range: TextSelection, replacement: string) =>
                  replaceRange(client.id, range, replacement)}
                onSelectionChange={(next: TextSelection) =>
                  updateSelection(client.id, next)}
              />
            {/each}
          </div>
        </div>

        <RightInspector
          comments={commentRanges}
          logs={networkLogs}
          {selectedCommentId}
          stats={activeByteStats}
          gzipStats={activeGzipStats}
          onSelectComment={selectComment}
        />
      </div>
    {/if}
  </section>

  <HistoryModal
    open={historyOpen}
    clientName={activeClient?.name ?? "client"}
    revision={historyRevision}
    maxRevision={maxHistoryRevision}
    delta={historyDelta}
    onClose={closeHistory}
    onRevisionChange={setHistoryRevision}
  />
</main>
