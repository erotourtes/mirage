import { describe, expect, it } from "vitest";
import { wordRangeAfter, wordRangeBefore } from "./editor-keys";

describe("wordRangeBefore", () => {
  it("selects the previous word and trailing spaces", () => {
    expect(wordRangeBefore("alpha beta  ", 12)).toEqual({ start: 6, end: 12 });
  });

  it("uses scalar indexes for emoji", () => {
    expect(wordRangeBefore("a 😀 beta", 4)).toEqual({ start: 2, end: 4 });
  });

  it("selects punctuation runs separately from words", () => {
    expect(wordRangeBefore("alpha --", 8)).toEqual({ start: 6, end: 8 });
  });
});

describe("wordRangeAfter", () => {
  it("selects the next word and leading spaces", () => {
    expect(wordRangeAfter("alpha  beta", 5)).toEqual({ start: 5, end: 11 });
  });

  it("uses scalar indexes for emoji", () => {
    expect(wordRangeAfter("a 😀 beta", 1)).toEqual({ start: 1, end: 3 });
  });

  it("selects punctuation runs separately from words", () => {
    expect(wordRangeAfter("alpha -- beta", 5)).toEqual({ start: 5, end: 8 });
  });
});
