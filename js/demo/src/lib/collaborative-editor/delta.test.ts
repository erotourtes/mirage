import { describe, expect, it } from "vitest";
import {
  clampSelection,
  clampSelectionToLength,
  commentsFromDelta,
  deltaText,
} from "./delta.ts";
import type { CommentRecord, DeltaOp } from "./types.ts";

describe("deltaText", () => {
  it("joins delta inserts without changing whitespace", () => {
    const delta: DeltaOp[] = [
      { insert: "Mirage" },
      { insert: "\n\n" },
      { insert: "local editor" },
    ];

    expect(deltaText(delta)).toBe("Mirage\n\nlocal editor");
  });

  it("returns an empty string for an empty delta", () => {
    expect(deltaText([])).toBe("");
  });
});

describe("commentsFromDelta", () => {
  it("builds comment ranges from delta attributes and metadata", () => {
    const comments: CommentRecord[] = [
      { id: "c1", authorClientId: 7, body: "check this" },
    ];
    const delta: DeltaOp[] = [
      { insert: "hello " },
      { insert: "world", attributes: { comment: "c1" } },
      { insert: "!" },
    ];

    expect(commentsFromDelta(delta, comments)).toEqual([
      {
        id: "c1",
        body: "check this",
        authorClientId: 7,
        start: 6,
        end: 11,
        snippet: "world",
      },
    ]);
  });

  it("merges adjacent ops for the same comment", () => {
    const comments: CommentRecord[] = [
      { id: "c1", authorClientId: 1, body: "split comment" },
    ];
    const delta: DeltaOp[] = [
      { insert: "a" },
      { insert: "bc", attributes: { comment: "c1", bold: "true" } },
      { insert: "de", attributes: { comment: "c1", color: "#67e8f9" } },
    ];

    expect(commentsFromDelta(delta, comments)).toEqual([
      {
        id: "c1",
        body: "split comment",
        authorClientId: 1,
        start: 1,
        end: 5,
        snippet: "bcde",
      },
    ]);
  });

  it("uses scalar indexes for ranges containing emoji", () => {
    const delta: DeltaOp[] = [
      { insert: "a😀" },
      { insert: "b", attributes: { comment: "c1" } },
    ];

    expect("a😀".length).toBe(3);
    expect(commentsFromDelta(delta, [])).toEqual([
      {
        id: "c1",
        body: "Comment",
        authorClientId: 0,
        start: 2,
        end: 3,
        snippet: "b",
      },
    ]);
  });
});

describe("clampSelection", () => {
  it("normalizes reversed ranges", () => {
    expect(clampSelection(8, 2, "0123456789")).toEqual({ start: 2, end: 8 });
  });

  it("clamps ranges to scalar text bounds", () => {
    expect(clampSelection(-10, 10, "a😀b")).toEqual({ start: 0, end: 3 });
  });

  it("keeps collapsed selections collapsed after clamping", () => {
    expect(clampSelection(100, 100, "abc")).toEqual({ start: 3, end: 3 });
  });

  it("clamps directly to a known scalar length", () => {
    expect(clampSelectionToLength(-4, 12, 5)).toEqual({ start: 0, end: 5 });
  });
});
