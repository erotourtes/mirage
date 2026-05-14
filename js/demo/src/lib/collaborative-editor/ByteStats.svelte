<script lang="ts">
  import {
    formatBytes,
    type ClientByteStats,
    type ClientGzipStats,
  } from "./byte-stats";

  type Props = { stats: ClientByteStats | null; gzipStats: ClientGzipStats };

  let { stats, gzipStats }: Props = $props();

  function gzipLabel(bytes: number | null): string {
    if (!gzipStats.supported) return "n/a";
    if (bytes !== null) return formatBytes(bytes);
    return gzipStats.pending ? "..." : "paused";
  }
</script>

{#if stats}
  <div class="grid gap-1 text-sm">
    <div class="grid grid-cols-[1fr_6.5rem] gap-2">
      <span class="text-neutral-500">length</span>
      <span class="text-right text-neutral-100">{stats.textLength}</span>
    </div>
    <div class="grid grid-cols-[1fr_6.5rem] gap-2">
      <span class="text-neutral-500">text bytes</span>
      <span class="text-right text-neutral-100">
        {stats.textBytes === null ? "paused" : formatBytes(stats.textBytes)}
      </span>
    </div>
    <div class="grid grid-cols-[1fr_6.5rem] gap-2">
      <span class="text-neutral-500">full sync</span>
      <span class="text-right text-neutral-100">
        {stats.fullUpdateBytes === null
          ? "paused"
          : formatBytes(stats.fullUpdateBytes)}
      </span>
    </div>
    <div class="grid grid-cols-[1fr_6.5rem] gap-2">
      <span class="text-neutral-500">text gzip</span>
      <span class="text-right text-neutral-100">
        {gzipLabel(gzipStats.textGzipBytes)}
      </span>
    </div>
    <div class="grid grid-cols-[1fr_6.5rem] gap-2">
      <span class="text-neutral-500">full gzip</span>
      <span class="text-right text-neutral-100">
        {gzipLabel(gzipStats.fullUpdateGzipBytes)}
      </span>
    </div>
    <div class="grid grid-cols-[1fr_6.5rem] gap-2">
      <span class="text-neutral-500">pending</span>
      <span class="text-right text-neutral-100"
        >{formatBytes(stats.pendingBytes)}</span
      >
    </div>
    <div class="grid grid-cols-[1fr_6.5rem] gap-2">
      <span class="text-neutral-500">internal</span>
      <span class="text-right text-neutral-100">
        {formatBytes(stats.internalBytes)}
      </span>
    </div>
  </div>
{:else}
  <p class="px-1 py-2 text-sm text-neutral-500">no client</p>
{/if}
