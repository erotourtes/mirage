<script lang="ts">
  import type { Snippet } from "svelte";

  type Props = { title: string; open?: boolean; children: Snippet };

  let { title, open = true, children }: Props = $props();
  let expanded = $derived(open);
</script>

<section class="border-b border-neutral-700 last:border-b-0">
  <button
    class="grid w-full grid-cols-[1fr_2rem] items-center px-3 py-2 text-left text-xs text-neutral-400 hover:bg-neutral-900"
    type="button"
    onclick={() => {
      expanded = !expanded;
    }}
  >
    <span>{title}</span>
    <span class="text-right text-cyan-300">{expanded ? "-" : "+"}</span>
  </button>
  {#if expanded}
    <div class="p-2">
      {@render children()}
    </div>
  {/if}
</section>
