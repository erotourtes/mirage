<script lang="ts">
  import type { DeltaOp } from "./types";

  type Props = {
    open: boolean;
    clientName: string;
    revision: number;
    maxRevision: number;
    delta: DeltaOp[];
    onRevisionChange: (revision: number) => void;
    onClose: () => void;
  };

  let {
    open,
    clientName,
    revision,
    maxRevision,
    delta,
    onRevisionChange,
    onClose,
  }: Props = $props();
</script>

{#if open}
  <div
    class="fixed inset-0 z-20 grid place-items-center bg-black/70 p-4"
    role="presentation"
    onclick={(event) => {
      if (event.currentTarget === event.target) onClose();
    }}
  >
    <div
      class="w-full max-w-3xl border border-neutral-600 bg-neutral-950 text-neutral-100"
      role="dialog"
      aria-modal="true"
      aria-label="Document history"
    >
      <header
        class="flex items-center justify-between border-b border-neutral-700 px-4 py-3"
      >
        <div>
          <h2 class="text-base font-bold">history: {clientName}</h2>
          <p class="text-xs text-neutral-500">
            revision {revision} / {maxRevision}
          </p>
        </div>
        <button
          class="border border-neutral-600 px-2 py-1 text-sm hover:bg-neutral-900"
          type="button"
          onclick={onClose}
        >
          close
        </button>
      </header>

      <div
        class="max-h-[60svh] overflow-auto p-4 text-sm leading-6 whitespace-pre-wrap"
      >
        {#each delta as op, index (`history-${index}-${op.insert.length}`)}
          <span
            class:bg-yellow-900={Boolean(op.attributes?.comment)}
            class:font-bold={op.attributes?.bold === "true"}
            style:color={op.attributes?.color}>{op.insert}</span
          >
        {/each}
      </div>

      <footer class="border-t border-neutral-700 px-4 py-3">
        <input
          class="channel-range w-full"
          max={maxRevision}
          min="0"
          step="1"
          style:--range-fill={maxRevision === 0
            ? "0%"
            : `${(revision / maxRevision) * 100}%`}
          type="range"
          value={revision}
          oninput={(event) =>
            onRevisionChange(event.currentTarget.valueAsNumber)}
        />
      </footer>
    </div>
  </div>
{/if}

<style>
  .channel-range {
    height: 1.25rem;
    appearance: none;
    background: transparent;
  }

  .channel-range:focus-visible {
    outline: 2px solid rgb(103 232 249);
    outline-offset: 2px;
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
