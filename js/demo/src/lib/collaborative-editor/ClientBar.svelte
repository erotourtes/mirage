<script lang="ts">
  import type { EditorClient } from "./types";

  type Props = {
    clients: EditorClient[];
    activeClientId: number | null;
    compareClients: boolean;
    performanceMode: boolean;
    onSelect: (clientId: number) => void;
    onAddClient: () => void;
    onCompareChange: (compareClients: boolean) => void;
    onPerformanceModeChange: (performanceMode: boolean) => void;
    onRemoveClient: (clientId: number) => void;
    onReset: () => void;
  };

  let {
    clients,
    activeClientId,
    compareClients,
    performanceMode,
    onSelect,
    onAddClient,
    onCompareChange,
    onPerformanceModeChange,
    onRemoveClient,
    onReset,
  }: Props = $props();
</script>

<aside class="border border-neutral-700 bg-neutral-950">
  <div class="border-b border-neutral-700 px-3 py-2 text-xs text-neutral-400">
    clients
  </div>
  <div class="space-y-1 p-2">
    {#each clients as client (client.id)}
      <div
        class="grid grid-cols-[minmax(0,1fr)_2rem] border"
        class:border-cyan-500={client.id === activeClientId}
        class:border-neutral-700={client.id !== activeClientId}
      >
        <button
          class="grid min-w-0 grid-cols-[1fr_auto] gap-2 px-2 py-2 text-left text-sm hover:bg-neutral-900"
          type="button"
          onclick={() => onSelect(client.id)}
        >
          <span class="truncate">{client.name}</span>
          <span
            class:text-green-400={client.connected}
            class:text-red-400={!client.connected}
          >
            {client.connected ? "online" : "offline"}
          </span>
          <span class="col-span-2 text-xs text-neutral-500">
            rev {client.doc.currentRevision.toString()} / pending {client
              .pendingUpdates.length}
          </span>
        </button>
        <button
          aria-label={`remove ${client.name}`}
          class="border-l border-neutral-800 text-sm text-neutral-500 hover:bg-red-950 hover:text-red-200 disabled:cursor-not-allowed disabled:hover:bg-transparent disabled:hover:text-neutral-500"
          disabled={clients.length <= 1}
          type="button"
          onclick={() => onRemoveClient(client.id)}
        >
          x
        </button>
      </div>
    {/each}

    <button
      class="mt-2 w-full border border-neutral-600 px-2 py-2 text-sm hover:bg-neutral-900"
      type="button"
      onclick={onAddClient}
    >
      + connect client
    </button>
  </div>

  <div class="border-t border-neutral-700 p-2">
    <label class="flex items-center gap-2 text-sm">
      <input
        class="channel-checkbox"
        checked={compareClients}
        type="checkbox"
        onchange={(event) => onCompareChange(event.currentTarget.checked)}
      />
      compare clients
    </label>
    <label class="mt-2 flex items-center gap-2 text-sm">
      <input
        class="channel-checkbox"
        checked={performanceMode}
        type="checkbox"
        onchange={(event) =>
          onPerformanceModeChange(event.currentTarget.checked)}
      />
      performance mode
    </label>
  </div>

  <div class="border-t border-neutral-700 p-2">
    <button
      class="w-full border border-red-800 px-2 py-2 text-sm text-red-200 hover:bg-red-950"
      type="button"
      onclick={onReset}
    >
      reset session
    </button>
  </div>
</aside>

<style>
  .channel-checkbox {
    width: 1rem;
    height: 1rem;
    appearance: none;
    border: 1px solid rgb(82 82 82);
    background: rgb(10 10 10);
    box-shadow: inset 0 0 0 2px rgb(10 10 10);
  }

  .channel-checkbox:checked {
    border-color: rgb(34 211 238);
    background: rgb(34 211 238);
  }

  .channel-checkbox:focus-visible {
    outline: 2px solid rgb(103 232 249);
    outline-offset: 2px;
  }
</style>
