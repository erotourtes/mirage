<script lang="ts">
  import { wordRangeAfter, wordRangeBefore } from "./editor-keys";
  import { getEditorSelection, setEditorSelection } from "./selection";
  import type { DeltaOp, TextSelection } from "./types";

  type Props = {
    delta: DeltaOp[];
    label?: string;
    text: string;
    selectedCommentId: string | null;
    selection: TextSelection;
    selectionVersion: number;
    onSelectionChange: (selection: TextSelection) => void;
    onReplace: (selection: TextSelection, text: string) => void;
    onBoldShortcut: () => void;
  };

  let {
    delta,
    label = "Collaborative editor",
    text,
    selectedCommentId,
    selection,
    selectionVersion,
    onSelectionChange,
    onReplace,
    onBoldShortcut,
  }: Props = $props();

  let editor: HTMLDivElement | undefined = $state();

  $effect(() => {
    track(selectionVersion);
    if (!editor || document.activeElement !== editor) return;

    queueMicrotask(() => {
      if (editor) setEditorSelection(editor, text, selection);
    });
  });

  function track(_value: unknown): void {}

  function readSelection(): TextSelection | null {
    if (!editor) return null;
    const current = getEditorSelection(editor);
    if (current) onSelectionChange(current);
    return current;
  }

  function readSelectionSoon(): void {
    requestAnimationFrame(() => {
      readSelection();
    });
  }

  $effect(() => {
    document.addEventListener("selectionchange", readSelectionSoon);
    return () => {
      document.removeEventListener("selectionchange", readSelectionSoon);
    };
  });

  function handleBeforeInput(event: InputEvent) {
    if (!editor) return;

    const current = getEditorSelection(editor) ?? selection;
    const inputType = event.inputType;

    if (inputType === "insertText" || inputType === "insertCompositionText") {
      event.preventDefault();
      onReplace(current, event.data ?? "");
      return;
    }

    if (inputType === "insertLineBreak" || inputType === "insertParagraph") {
      event.preventDefault();
      onReplace(current, "\n");
      return;
    }

    if (inputType === "deleteContentBackward") {
      event.preventDefault();
      if (current.start !== current.end) {
        onReplace(current, "");
        return;
      }
      if (current.start > 0) {
        onReplace({ start: current.start - 1, end: current.start }, "");
      }
      return;
    }

    if (inputType === "deleteContentForward") {
      event.preventDefault();
      if (current.start !== current.end) {
        onReplace(current, "");
        return;
      }

      const length = [...text].length;
      if (current.start < length) {
        onReplace({ start: current.start, end: current.start + 1 }, "");
      }
    }
  }

  function handlePaste(event: ClipboardEvent) {
    event.preventDefault();
    const current = readSelection() ?? selection;
    onReplace(current, event.clipboardData?.getData("text/plain") ?? "");
  }

  function handleKeydown(event: KeyboardEvent) {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "b") {
      event.preventDefault();
      readSelection();
      onBoldShortcut();
      return;
    }

    if ((event.ctrlKey || event.metaKey) && event.key === "Backspace") {
      event.preventDefault();
      const current = readSelection() ?? selection;
      onReplace(
        current.start === current.end
          ? wordRangeBefore(text, current.start)
          : current,
        "",
      );
      return;
    }

    if ((event.ctrlKey || event.metaKey) && event.key === "Delete") {
      event.preventDefault();
      const current = readSelection() ?? selection;
      onReplace(
        current.start === current.end
          ? wordRangeAfter(text, current.start)
          : current,
        "",
      );
    }
  }
</script>

<div
  class="flex min-h-0 flex-1 flex-col border border-neutral-700 bg-neutral-950"
>
  <div class="border-b border-neutral-700 px-3 py-2 text-xs text-neutral-400">
    buffer.txt
  </div>
  <div
    bind:this={editor}
    class="channel-scrollbar editor-scrollbar-left min-h-[14rem] flex-1 overflow-auto text-[15px] leading-6 whitespace-pre-wrap outline-none selection:bg-cyan-700/60"
    contenteditable="true"
    role="textbox"
    spellcheck="false"
    tabindex="0"
    aria-label={label}
    onbeforeinput={handleBeforeInput}
    onkeydown={handleKeydown}
    onkeyup={readSelectionSoon}
    onmouseup={readSelectionSoon}
    onfocus={readSelectionSoon}
    onpaste={handlePaste}
  >
    {#if delta.length === 0}
      <span class="text-neutral-500">&ZeroWidthSpace;</span>
    {:else}
      {#each delta as op, index (`${index}-${op.insert.length}-${op.attributes?.comment ?? ""}-${op.attributes?.bold ?? ""}-${op.attributes?.color ?? ""}`)}
        <span
          class:bg-yellow-900={op.attributes?.comment &&
            op.attributes.comment !== selectedCommentId}
          class:bg-yellow-500={op.attributes?.comment === selectedCommentId}
          class:text-black={op.attributes?.comment === selectedCommentId}
          class:font-bold={op.attributes?.bold === "true"}
          style:color={op.attributes?.comment === selectedCommentId
            ? undefined
            : op.attributes?.color}
          data-comment={op.attributes?.comment ?? undefined}>{op.insert}</span
        >
      {/each}
    {/if}
  </div>
</div>
