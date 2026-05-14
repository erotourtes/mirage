<script lang="ts">
  import { formatBytes } from "./byte-stats";
  import type { NetworkLogEntry } from "./types";

  type Props = { logs: NetworkLogEntry[] };

  let { logs }: Props = $props();

  function timeLabel(time: number): string {
    return new Date(time).toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
  }

  function routeLabel(log: NetworkLogEntry): string {
    switch (log.kind) {
      case "local":
        return `client-${log.clientId}`;
      case "flush":
      case "encoded":
      case "queued":
      case "scheduled":
      case "applied":
        return `${log.sourceId}->${log.targetId}`;
    }
  }

  function detailLabel(log: NetworkLogEntry): string {
    switch (log.kind) {
      case "local":
        return `${log.operation} [${log.start}:${log.end}]`;
      case "encoded":
        return `encoded ${formatBytes(log.bytes)}`;
      case "queued":
        return `queued ${formatBytes(log.bytes)} ${log.reason}`;
      case "scheduled":
        return `send ${formatBytes(log.bytes)} ${log.latencyMs}ms ${log.copy}/${log.copies}`;
      case "applied":
        return `applied ${formatBytes(log.bytes)}`;
      case "flush":
        return `flush ${log.count}`;
    }
  }
</script>

{#if logs.length === 0}
  <p class="px-1 py-2 text-sm text-neutral-500">no log entries</p>
{:else}
  <div class="channel-scrollbar max-h-80 overflow-auto text-xs">
    {#each logs as log (log.id)}
      <div
        class="grid min-w-max grid-cols-[4.75rem_5.5rem_4.25rem_minmax(20rem,max-content)] gap-2 border-b border-neutral-800 py-1 pr-2 last:border-b-0"
      >
        <span class="whitespace-nowrap text-neutral-500">
          {timeLabel(log.time)}
        </span>
        <span class="whitespace-nowrap text-cyan-300">{log.kind}</span>
        <span class="whitespace-nowrap text-neutral-400">
          {routeLabel(log)}
        </span>
        <span class="whitespace-nowrap text-neutral-100">
          {detailLabel(log)}
        </span>
      </div>
    {/each}
  </div>
{/if}
