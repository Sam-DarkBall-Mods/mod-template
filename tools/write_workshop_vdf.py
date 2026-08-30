#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def vdf_escape(value: str) -> str:
    normalized = value.replace("\r\n", "\n").replace("\r", "\n")
    return (
        normalized.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--content", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    change_note = parser.add_mutually_exclusive_group(required=True)
    change_note.add_argument("--change-note")
    change_note.add_argument("--change-note-file", type=Path)
    args = parser.parse_args()

    meta = (ROOT / "meta.cpp").read_text(encoding="utf-8")
    match = re.search(r"publishedid\s*=\s*(\d+)\s*;", meta)
    if match is None or int(match.group(1)) == 0:
        raise SystemExit("meta.cpp does not contain a production Workshop ID")

    content = args.content.resolve()
    if not content.is_dir():
        raise SystemExit(f"Workshop content directory does not exist: {content}")

    if args.change_note_file is None:
        note = args.change_note
    else:
        note = args.change_note_file.read_text(encoding="utf-8")
    note = note.strip()
    if not note:
        raise SystemExit("Workshop change note is empty")

    args.output.write_text(
        "\n".join(
            [
                '"workshopitem"',
                "{",
                '    "appid" "107410"',
                f'    "publishedfileid" "{match.group(1)}"',
                f'    "contentfolder" "{vdf_escape(str(content))}"',
                f'    "changenote" "{vdf_escape(note)}"',
                "}",
                "",
            ]
        ),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
