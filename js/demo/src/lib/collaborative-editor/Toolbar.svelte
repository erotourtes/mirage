<script lang="ts">
  import { TEXT_COLORS, type TextColor } from "./types";

  type Props = {
    canFormat: boolean;
    onBold: () => void;
    onColor: (color: TextColor) => void;
    onComment: () => void;
    onHistory: () => void;
  };

  let { canFormat, onBold, onColor, onComment, onHistory }: Props = $props();
  let customColor = $state<TextColor>(TEXT_COLORS[0].value);

  function previewCustomColor(value: string) {
    customColor = value as TextColor;
  }

  function chooseCustomColor(value: string) {
    previewCustomColor(value);
    onColor(customColor);
  }
</script>

<div
  class="flex flex-wrap items-center gap-2 border-x border-t border-neutral-700 bg-neutral-900 px-3 py-2"
>
  <button
    class="border border-neutral-600 px-3 py-1 text-sm text-neutral-100 hover:bg-neutral-800 disabled:text-neutral-600"
    disabled={!canFormat}
    type="button"
    onclick={onBold}
  >
    BOLD
  </button>
  <div class="flex items-center gap-1 border-l border-neutral-700 pl-2">
    {#each TEXT_COLORS as color (color.value)}
      <button
        class="size-7 border border-neutral-600 hover:border-neutral-100 disabled:opacity-40"
        style:background-color={color.value}
        disabled={!canFormat}
        type="button"
        title={`Color ${color.name}`}
        aria-label={`Color ${color.name}`}
        onclick={() => onColor(color.value)}
      ></button>
    {/each}
    <input
      class="size-7 cursor-pointer border border-neutral-600 bg-neutral-950 p-0 hover:border-neutral-100 disabled:cursor-default disabled:opacity-40"
      disabled={!canFormat}
      list="text-color-presets"
      type="color"
      title="Custom color"
      aria-label="Custom color"
      value={customColor}
      oninput={(event) => previewCustomColor(event.currentTarget.value)}
      onchange={(event) => chooseCustomColor(event.currentTarget.value)}
    />
    <datalist id="text-color-presets">
      {#each TEXT_COLORS as color (color.value)}
        <option value={color.value} label={color.name}></option>
      {/each}
    </datalist>
  </div>
  <button
    class="border border-neutral-600 px-3 py-1 text-sm text-neutral-100 hover:bg-neutral-800 disabled:text-neutral-600"
    disabled={!canFormat}
    type="button"
    onclick={onComment}
  >
    COMMENT
  </button>
  <button
    class="ml-auto border border-neutral-600 px-3 py-1 text-sm text-neutral-100 hover:bg-neutral-800"
    type="button"
    onclick={onHistory}
  >
    HISTORY
  </button>
</div>
