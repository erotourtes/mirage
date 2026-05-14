<script lang="ts">
  import type { EditorClient } from "./types";

  type Props = {
    client: EditorClient | null;
    onConnectedChange: (connected: boolean) => void;
    onLatencyChange: (latencyMs: number) => void;
    onDuplicateChange: (duplicateSend: boolean) => void;
  };

  let { client, onConnectedChange, onLatencyChange, onDuplicateChange }: Props =
    $props();
</script>

<section class="border-x border-neutral-700 bg-neutral-950 px-3 py-2">
  {#if client}
    <div
      class="grid gap-3 text-sm md:grid-cols-[auto_1fr_auto] md:items-center"
    >
      <label class="flex items-center gap-2">
        <input
          class="channel-checkbox"
          checked={client.connected}
          type="checkbox"
          onchange={(event) => onConnectedChange(event.currentTarget.checked)}
        />
        connected
      </label>

      <label class="grid gap-1">
        <span class="text-xs text-neutral-500"
          >latency {client.latencyMs}ms</span
        >
        <input
          class="channel-range"
          max="3000"
          min="0"
          step="100"
          style:--range-fill={`${(client.latencyMs / 3000) * 100}%`}
          type="range"
          value={client.latencyMs}
          oninput={(event) =>
            onLatencyChange(event.currentTarget.valueAsNumber)}
        />
      </label>

      <label class="flex items-center gap-2">
        <input
          class="channel-checkbox"
          checked={client.duplicateSend}
          type="checkbox"
          onchange={(event) => onDuplicateChange(event.currentTarget.checked)}
        />
        duplicate send
      </label>
    </div>
  {:else}
    <p class="text-sm text-neutral-500">no client</p>
  {/if}
</section>

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

  .channel-checkbox:focus-visible,
  .channel-range:focus-visible {
    outline: 2px solid rgb(103 232 249);
    outline-offset: 2px;
  }

  .channel-range {
    width: 100%;
    height: 1.25rem;
    appearance: none;
    background: transparent;
  }

  .channel-range::-webkit-slider-runnable-track {
    height: 0.375rem;
    border: 1px solid rgb(82 82 82);
    background: linear-gradient(
      to right,
      rgb(34 211 238) 0 var(--range-fill),
      rgb(38 38 38) var(--range-fill) 100%
    );
  }

  .channel-range::-webkit-slider-thumb {
    width: 0.875rem;
    height: 1rem;
    margin-top: -0.375rem;
    appearance: none;
    border: 1px solid rgb(103 232 249);
    background: rgb(10 10 10);
  }

  .channel-range::-moz-range-track {
    height: 0.375rem;
    border: 1px solid rgb(82 82 82);
    background: rgb(38 38 38);
  }

  .channel-range::-moz-range-progress {
    height: 0.375rem;
    background: rgb(34 211 238);
  }

  .channel-range::-moz-range-thumb {
    width: 0.875rem;
    height: 1rem;
    border: 1px solid rgb(103 232 249);
    border-radius: 0;
    background: rgb(10 10 10);
  }
</style>
