import type { CommentRange, CommentRecord, DeltaOp } from "./types";

export function deltaText(delta: DeltaOp[]): string {
  return delta.map((op) => op.insert).join("");
}

export function commentsFromDelta(
  delta: DeltaOp[],
  comments: CommentRecord[],
): CommentRange[] {
  const records = new Map(comments.map((comment) => [comment.id, comment]));
  const ranges = new Map<string, CommentRange>();
  let index = 0;

  for (const op of delta) {
    const commentId = op.attributes?.comment;
    const start = index;
    const end = index + [...op.insert].length;
    index = end;

    if (!commentId) continue;

    const record = records.get(commentId);
    const existing = ranges.get(commentId);
    if (existing) {
      existing.end = end;
      existing.snippet += op.insert;
      continue;
    }

    ranges.set(commentId, {
      id: commentId,
      body: record?.body ?? "Comment",
      authorClientId: record?.authorClientId ?? 0,
      start,
      end,
      snippet: op.insert,
    });
  }

  return [...ranges.values()];
}

export function clampSelection(start: number, end: number, text: string) {
  return clampSelectionToLength(start, end, [...text].length);
}

export function clampSelectionToLength(
  start: number,
  end: number,
  length: number,
) {
  const safeStart = Math.max(0, Math.min(start, length));
  const safeEnd = Math.max(0, Math.min(end, length));

  return {
    start: Math.min(safeStart, safeEnd),
    end: Math.max(safeStart, safeEnd),
  };
}
