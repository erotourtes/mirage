<script lang="ts">
  import ByteStats from "./ByteStats.svelte";
  import CommentsPane from "./CommentsPane.svelte";
  import InspectorSection from "./InspectorSection.svelte";
  import NetworkLog from "./NetworkLog.svelte";
  import type { ClientByteStats, ClientGzipStats } from "./byte-stats";
  import type { CommentRange, NetworkLogEntry } from "./types";

  type Props = {
    comments: CommentRange[];
    selectedCommentId: string | null;
    stats: ClientByteStats | null;
    gzipStats: ClientGzipStats;
    logs: NetworkLogEntry[];
    onSelectComment: (commentId: string | null) => void;
  };

  let {
    comments,
    selectedCommentId,
    stats,
    gzipStats,
    logs,
    onSelectComment,
  }: Props = $props();
</script>

<aside
  class="channel-scrollbar min-h-0 overflow-auto border border-neutral-700 bg-neutral-950"
>
  <InspectorSection title="comments">
    <CommentsPane
      {comments}
      {selectedCommentId}
      onSelect={onSelectComment}
      embedded
    />
  </InspectorSection>

  <InspectorSection title="storage">
    <ByteStats {stats} {gzipStats} />
  </InspectorSection>

  <InspectorSection title="network log" open={false}>
    <NetworkLog {logs} />
  </InspectorSection>
</aside>
