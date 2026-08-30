#!/usr/bin/env python3
from __future__ import annotations

import sys
import tomllib
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RELEASE_ROOT = ROOT / ".hemttout" / "release"
ARCHIVE_ROOT = ROOT / "releases"
LEGAL_FILES = (
    (ROOT / "LICENSE", Path("LICENSE")),
    (ROOT / "LICENSES" / "APL-SA.txt", Path("ASSET_LICENSE.txt")),
    (ROOT / "THIRD_PARTY_NOTICES.md", Path("THIRD_PARTY_NOTICES.txt")),
)
LEGAL_DESTINATIONS = {destination.as_posix() for _, destination in LEGAL_FILES}


def release_mod_folder() -> str:
    with (ROOT / ".hemtt" / "project.toml").open("rb") as project_file:
        project = tomllib.load(project_file)
    folder = project["hemtt"]["release"]["folder"]
    return folder if folder.startswith("@") else f"@{folder}"


def collect_release_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if path.suffix.lower() == ".md":
            continue
        if relative.parts[0] == "LICENSES":
            continue
        if relative.as_posix() in LEGAL_DESTINATIONS:
            continue
        files.append(path)
    return sorted(files)


def write_archive(archive: Path, files: list[Path], mod_folder: str) -> None:
    temporary = archive.with_suffix(".tmp")
    with zipfile.ZipFile(
        temporary,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
        allowZip64=True,
    ) as output:
        for path in files:
            relative = path.relative_to(RELEASE_ROOT)
            output.write(path, Path(mod_folder) / relative)
        for source, destination in LEGAL_FILES:
            output.write(source, Path(mod_folder) / destination)
    temporary.replace(archive)


def main() -> int:
    if not RELEASE_ROOT.is_dir():
        print("ERROR: HEMTT release folder not found", file=sys.stderr)
        return 1

    archives = sorted(ARCHIVE_ROOT.glob("*.zip"))
    if not archives:
        print("ERROR: HEMTT release archives not found", file=sys.stderr)
        return 1

    for source, _ in LEGAL_FILES:
        if not source.is_file():
            print(f"ERROR: Legal file not found: {source}", file=sys.stderr)
            return 1

    files = collect_release_files(RELEASE_ROOT)
    if not files:
        print("ERROR: HEMTT release folder is empty", file=sys.stderr)
        return 1

    mod_folder = release_mod_folder()
    for archive in archives:
        write_archive(archive, files, mod_folder)
        print(f"Packed {archive.name} with {len(files) + len(LEGAL_FILES)} file(s).")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
