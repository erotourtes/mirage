<script lang="ts">
  import { deltaText } from "./delta";
  import EditorPane from "./EditorPane.svelte";
  import NetworkPanel from "./NetworkPanel.svelte";
  import Toolbar from "./Toolbar.svelte";
  import type { EditorClient, TextColor, TextSelection } from "./types";

  type Props = {
    client: EditorClient;
    active: boolean;
    performanceMode: boolean;
    selectedCommentId: string | null;
    selection: TextSelection;
    selectionVersion: number;
    onBold: () => void;
    onColor: (color: TextColor) => void;
    onComment: () => void;
    onConnectedChange: (connected: boolean) => void;
    onDuplicateChange: (duplicateSend: boolean) => void;
    onFocus: () => void;
    onHistory: () => void;
    onLatencyChange: (latencyMs: number) => void;
    onReplace: (selection: TextSelection, text: string) => void;
    onSelectionChange: (selection: TextSelection) => void;
  };

  let {
    client,
    active,
    performanceMode,
    selectedCommentId,
    selection,
    selectionVersion,
    onBold,
    onColor,
    onComment,
    onConnectedChange,
    onDuplicateChange,
    onFocus,
    onHistory,
    onLatencyChange,
    onReplace,
    onSelectionChange,
  }: Props = $props();

  const windowBefore = 2_000;
  const windowSize = 6_000;

  let renderStart = $state(0);

  $effect(() => {
    const fullLength = Number(client.doc.length);
    if (!performanceMode || fullLength <= windowSize) {
      if (renderStart !== 0) renderStart = 0;
      return;
    }

    const maxStart = Math.max(0, fullLength - windowSize);
    const cursor = Math.max(0, Math.min(fullLength, selection.end));
    const renderEnd = renderStart + windowSize;
    let nextStart = renderStart;

    if (cursor < renderStart) {
      nextStart = cursor - windowBefore;
    } else if (cursor > renderEnd) {
      nextStart = cursor - (windowSize - windowBefore);
    }

    nextStart = Math.max(0, Math.min(nextStart, maxStart));
    if (nextStart !== renderStart) renderStart = nextStart;
  });

  let renderEnd = $derived.by(() => {
    if (!performanceMode) return Number(client.doc.length);

    return Math.min(Number(client.doc.length), renderStart + windowSize);
  });
  let delta = $derived(
    performanceMode
      ? client.doc.toDeltaRange(renderStart, renderEnd, {
          includeLeadingAttrs: false,
        })
      : client.doc.toDelta(),
  );
  let text = $derived(deltaText(delta));
  let textLength = $derived([...text].length);
  let localSelection = $derived({
    start: Math.max(0, Math.min(textLength, selection.start - renderStart)),
    end: Math.max(0, Math.min(textLength, selection.end - renderStart)),
  });

  function toGlobalSelection(next: TextSelection): TextSelection {
    return { start: next.start + renderStart, end: next.end + renderStart };
  }
</script>

<section class="flex min-h-[28rem] max-h-[44rem] min-w-0 flex-col">
  <button
    class="flex items-center justify-between border border-b-0 px-3 py-2 text-left text-xs hover:bg-neutral-900"
    class:border-cyan-500={active}
    class:border-neutral-700={!active}
    type="button"
    onclick={onFocus}
  >
    <span class="font-bold text-neutral-100">{client.name}</span>
    <span class="text-neutral-500"
      >rev {client.doc.currentRevision.toString()}</span
    >
  </button>
  <NetworkPanel
    {client}
    {onConnectedChange}
    {onDuplicateChange}
    {onLatencyChange}
  />
  <Toolbar
    canFormat={selection.start !== selection.end}
    {onBold}
    {onColor}
    {onComment}
    {onHistory}
  />
  <EditorPane
    {delta}
    label={`Collaborative editor ${client.name}`}
    {text}
    {selectedCommentId}
    selection={localSelection}
    {selectionVersion}
    onBoldShortcut={onBold}
    onReplace={(range: TextSelection, replacement: string) =>
      onReplace(toGlobalSelection(range), replacement)}
    onSelectionChange={(next: TextSelection) =>
      onSelectionChange(toGlobalSelection(next))}
  />
</section>
