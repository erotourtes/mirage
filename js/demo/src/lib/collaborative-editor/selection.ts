import type { TextSelection } from "./types";

export function scalarIndexFromUtf16(
  text: string,
  utf16Offset: number,
): number {
  let scalarIndex = 0;
  let offset = 0;

  while (offset < utf16Offset && offset < text.length) {
    const codePoint = text.codePointAt(offset) ?? 0;
    offset += codePoint > 0xffff ? 2 : 1;
    scalarIndex += 1;
  }

  return scalarIndex;
}

export function utf16OffsetFromScalar(
  text: string,
  scalarIndex: number,
): number {
  let offset = 0;
  let current = 0;

  while (offset < text.length && current < scalarIndex) {
    const codePoint = text.codePointAt(offset) ?? 0;
    offset += codePoint > 0xffff ? 2 : 1;
    current += 1;
  }

  return offset;
}

export function getEditorSelection(root: HTMLElement): TextSelection | null {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return null;

  const range = selection.getRangeAt(0);
  if (!root.contains(range.commonAncestorContainer)) return null;

  const fullText = root.textContent ?? "";
  const beforeStart = document.createRange();
  beforeStart.selectNodeContents(root);
  beforeStart.setEnd(range.startContainer, range.startOffset);

  const beforeEnd = document.createRange();
  beforeEnd.selectNodeContents(root);
  beforeEnd.setEnd(range.endContainer, range.endOffset);

  return {
    start: scalarIndexFromUtf16(fullText, beforeStart.toString().length),
    end: scalarIndexFromUtf16(fullText, beforeEnd.toString().length),
  };
}

export function setEditorSelection(
  root: HTMLElement,
  text: string,
  selection: TextSelection,
): void {
  const range = document.createRange();
  const domStart = findTextPosition(
    root,
    utf16OffsetFromScalar(text, selection.start),
  );
  const domEnd = findTextPosition(
    root,
    utf16OffsetFromScalar(text, selection.end),
  );

  range.setStart(domStart.node, domStart.offset);
  range.setEnd(domEnd.node, domEnd.offset);

  const windowSelection = window.getSelection();
  windowSelection?.removeAllRanges();
  windowSelection?.addRange(range);
}

function findTextPosition(
  root: HTMLElement,
  targetOffset: number,
): { node: Node; offset: number } {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let remaining = targetOffset;
  let current = walker.nextNode();

  while (current) {
    const length = current.textContent?.length ?? 0;
    if (remaining <= length) {
      return { node: current, offset: remaining };
    }

    remaining -= length;
    current = walker.nextNode();
  }

  return { node: root, offset: root.childNodes.length };
}
