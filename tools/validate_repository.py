#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_EXTENSIONS = {".cpp", ".h", ".hpp", ".inc", ".sqf"}
IGNORED_PARTS = {".git", ".hemttout", "releases", "__pycache__"}
PACKAGE_ROOTS = ("addons", "optionals")
FORBIDDEN_PACKAGE_NAMES = {".ds_store", "thumbs.db", ".gitkeep"}
FORBIDDEN_PACKAGE_SUFFIXES = {
    ".bak",
    ".tmp",
    ".orig",
    ".rej",
    ".psd",
    ".psb",
    ".xcf",
    ".blend",
    ".blend1",
}
FORBIDDEN_PACKAGE_MARKERS = (".bak.", ".back.", " - copy.")
REQUIRED_PACKAGE_EXCLUDES = (
    "**/.DS_Store",
    "**/Thumbs.db",
    "**/*.bak",
    "**/*.bak.*",
    "**/*.back.*",
    "**/*.tmp",
    "**/*.orig",
    "**/*.rej",
    "**/* - Copy.*",
    "**/*.psd",
    "**/*.psb",
    "**/*.xcf",
    "**/*.blend",
    "**/*.blend1",
    "**/.gitkeep",
)


def source_files() -> list[Path]:
    return sorted(
        path
        for path in ROOT.rglob("*")
        if path.is_file()
        and path.suffix.lower() in SOURCE_EXTENSIONS
        and not IGNORED_PARTS.intersection(path.relative_to(ROOT).parts)
    )


def package_files() -> list[Path]:
    return sorted(
        path
        for root_name in PACKAGE_ROOTS
        for path in (ROOT / root_name).rglob("*")
        if path.is_file()
    )


def is_forbidden_package_file(path: Path) -> bool:
    name = path.name.lower()
    return (
        name in FORBIDDEN_PACKAGE_NAMES
        or path.suffix.lower() in FORBIDDEN_PACKAGE_SUFFIXES
        or any(marker in name for marker in FORBIDDEN_PACKAGE_MARKERS)
    )


def main() -> int:
    files = source_files()
    if not files:
        print("ERROR: no SQF or Arma configuration files found", file=sys.stderr)
        return 1

    errors: list[str] = []
    for path in files:
        data = path.read_bytes()
        relative = path.relative_to(ROOT)
        if data.startswith((b"\xef\xbb\xbf", b"\xff\xfe", b"\xfe\xff")):
            errors.append(f"{relative}: byte-order mark is not allowed")

    for path in package_files():
        if is_forbidden_package_file(path):
            relative = path.relative_to(ROOT)
            errors.append(f"{relative}: backup or authoring file is not allowed in an addon")

    project = (ROOT / ".hemtt" / "project.toml").read_text(encoding="utf-8")
    for pattern in REQUIRED_PACKAGE_EXCLUDES:
        if f'"{pattern}"' not in project:
            errors.append(f".hemtt/project.toml: missing package exclude {pattern}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"Validated {len(files)} SQF/config source file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
