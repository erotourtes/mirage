import type { TextSelection } from "./types";

function isSpace(char: string): boolean {
  return /\s/u.test(char);
}

function isWord(char: string): boolean {
  return /[\p{L}\p{N}_]/u.test(char);
}

function clampCursor(cursor: number, chars: string[]): number {
  return Math.max(0, Math.min(cursor, chars.length));
}

export function wordRangeBefore(text: string, cursor: number): TextSelection {
  const chars = [...text];
  const end = clampCursor(cursor, chars);
  let start = end;

  while (start > 0 && isSpace(chars[start - 1] ?? "")) start -= 1;
  if (start === 0) return { start, end };

  const word = isWord(chars[start - 1] ?? "");
  while (start > 0) {
    const char = chars[start - 1] ?? "";
    if (isSpace(char) || isWord(char) !== word) break;
    start -= 1;
  }

  return { start, end };
}

export function wordRangeAfter(text: string, cursor: number): TextSelection {
  const chars = [...text];
  const start = clampCursor(cursor, chars);
  let end = start;

  while (end < chars.length && isSpace(chars[end] ?? "")) end += 1;
  if (end === chars.length) return { start, end };

  const word = isWord(chars[end] ?? "");
  while (end < chars.length) {
    const char = chars[end] ?? "";
    if (isSpace(char) || isWord(char) !== word) break;
    end += 1;
  }

  return { start, end };
}
