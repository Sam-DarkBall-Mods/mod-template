from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_tool(name: str):
    path = ROOT / "tools" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


package_release = load_tool("package_release")
write_workshop_vdf = load_tool("write_workshop_vdf")


class ReleaseToolTests(unittest.TestCase):
    def test_release_archive_uses_flat_legal_files(self) -> None:
        destinations = [
            destination.as_posix()
            for _, destination in package_release.LEGAL_FILES
        ]
        self.assertEqual(
            destinations,
            ["LICENSE", "ASSET_LICENSE.txt", "THIRD_PARTY_NOTICES.txt"],
        )
        for source, _ in package_release.LEGAL_FILES:
            with self.subTest(source=source):
                self.assertTrue(source.is_file())

    def test_release_archive_excludes_markdown_and_licenses_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "addons").mkdir()
            (root / "LICENSES").mkdir()
            (root / "addons" / "mod.pbo").write_bytes(b"pbo")
            (root / "meta.cpp").write_text("meta", encoding="utf-8")
            (root / "LICENSE").write_text("license", encoding="utf-8")
            (root / "README.md").write_text("readme", encoding="utf-8")
            (root / "LICENSES" / "APL-SA.txt").write_text(
                "asset license", encoding="utf-8"
            )

            files = package_release.collect_release_files(root)
            relative = {path.relative_to(root).as_posix() for path in files}

        self.assertEqual(relative, {"addons/mod.pbo", "meta.cpp"})

    def test_vdf_escape_handles_multiline_release_notes(self) -> None:
        escaped = write_workshop_vdf.vdf_escape(
            'First line\r\n"Second line" C:\\Mods'
        )
        self.assertEqual(escaped, 'First line\\n\\"Second line\\" C:\\\\Mods')


if __name__ == "__main__":
    unittest.main()
