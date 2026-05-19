#!/usr/bin/env python3

import argparse
import re
import textwrap
from pathlib import Path


CALL_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_.-]*\(")
FIELD_RE = re.compile(r"^[^\s:]+:\s")


def indentation(line: str) -> str:
    return line[: len(line) - len(line.lstrip(" "))]


def is_plain_prose(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return False

    structural_prefixes = (
        "#",
        "=",
        "- ",
        "+ ",
        "/",
        "[",
        "]",
        "(",
        ")",
        "{",
        "}",
        ".",
        "`",
        "$",
    )
    if stripped.startswith(structural_prefixes):
        return False

    code_prefixes = (
        "let ",
        "set ",
        "show ",
        "if ",
        "else",
        "for ",
        "return ",
    )
    if stripped.startswith(code_prefixes):
        return False

    if stripped.endswith(("\\", "[", "(", "{")):
        return False

    if "#" in stripped:
        return False

    if CALL_RE.match(stripped) or FIELD_RE.match(stripped):
        return False

    return True


def reflow_paragraph(lines: list[str], width: int) -> list[str]:
    if not lines:
        return []

    indent = indentation(lines[0])
    text = " ".join(line.strip() for line in lines)
    available_width = max(width - len(indent), 20)
    wrapped = textwrap.wrap(
        text,
        width=available_width,
        break_long_words=False,
        break_on_hyphens=False,
    )
    return [f"{indent}{line}\n" for line in wrapped]


def reflow(content: str, width: int) -> str:
    result: list[str] = []
    paragraph: list[str] = []
    paragraph_indent: str | None = None
    in_raw = False
    in_math = False

    def flush() -> None:
        nonlocal paragraph, paragraph_indent
        result.extend(reflow_paragraph(paragraph, width))
        paragraph = []
        paragraph_indent = None

    for line in content.splitlines(keepends=True):
        stripped = line.strip()

        if stripped.startswith("```"):
            flush()
            result.append(line)
            in_raw = not in_raw
            continue

        if stripped == "$":
            flush()
            result.append(line)
            in_math = not in_math
            continue

        if in_raw or in_math:
            result.append(line)
            continue

        line_indent = indentation(line)
        if is_plain_prose(line) and (paragraph_indent in (None, line_indent)):
            paragraph.append(line)
            paragraph_indent = line_indent
        else:
            flush()
            result.append(line)

    flush()
    return "".join(result)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--line-width", "-w", type=int, default=80)
    args = parser.parse_args()

    for path in args.paths:
        original = path.read_text()
        formatted = reflow(original, args.line_width)
        if formatted != original:
            path.write_text(formatted)


if __name__ == "__main__":
    main()
