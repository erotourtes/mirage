<script lang="ts">
  import type { CommentRange } from "./types";

  type Props = {
    comments: CommentRange[];
    selectedCommentId: string | null;
    onSelect: (commentId: string | null) => void;
    embedded?: boolean;
  };

  let {
    comments,
    selectedCommentId,
    onSelect,
    embedded = false,
  }: Props = $props();
</script>

<aside
  class:border={embedded === false}
  class:border-neutral-700={embedded === false}
  class:bg-neutral-950={embedded === false}
>
  {#if !embedded}
    <div class="border-b border-neutral-700 px-3 py-2 text-xs text-neutral-400">
      comments
    </div>
  {/if}
  <div class="space-y-2 p-2">
    {#if comments.length === 0}
      <p class="px-1 py-2 text-sm text-neutral-500">no comments</p>
    {:else}
      {#each comments as comment (comment.id)}
        <button
          class="w-full border px-2 py-2 text-left text-sm hover:bg-neutral-900"
          class:border-yellow-400={comment.id === selectedCommentId}
          class:border-neutral-700={comment.id !== selectedCommentId}
          type="button"
          onclick={() =>
            onSelect(comment.id === selectedCommentId ? null : comment.id)}
        >
          <span class="block text-xs text-neutral-500">
            {comment.id} [{comment.start}:{comment.end}] by client-{comment.authorClientId}
          </span>
          <span class="mt-1 block text-neutral-100">{comment.body}</span>
          <span class="mt-2 block truncate text-xs text-yellow-300">
            {comment.snippet}
          </span>
        </button>
      {/each}
    {/if}
  </div>
</aside>
