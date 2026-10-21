#!/usr/bin/env python3
"""Execute Gallery's production rollover and close methods with UI effects isolated."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end].removeprefix("private ")


@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class PaletteRolloverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="nowhere-palette-rollover-")
        cls.addClassCleanup(cls.directory.cleanup)
        folder = Path(cls.directory.name)
        gallery = (ROOT / "Nowhere/Views/GalleryView.swift").read_text()
        notifications = (ROOT / "Nowhere/Views/Gallery/GalleryNotifications.swift").read_text()
        state = ""
        if "struct CanvasPalettePresentationState:" in notifications:
            state = declaration(notifications, "struct CanvasPalettePresentationState:")
        source = (ROOT / "Scripts/Fixtures/PaletteRolloverHarness.swift").read_text()
        for key, value in [
            ("STATE", state),
            ("CLOSE", declaration(gallery, "private func closeHappeningPalette()")),
            ("ROLLOVER", declaration(gallery, "private func rollOverCanvas(to newKey: String)")),
        ]:
            source = source.replace("/*__" + key + "__*/", value)
        script = folder / "main.swift"
        script.write_text(source)
        cls.binary = folder / "rollover"
        build = subprocess.run(["swiftc", "-module-cache-path", str(folder / "modules"), str(script), "-o", str(cls.binary)], capture_output=True, text=True, timeout=45)
        if build.returncode:
            raise AssertionError(build.stdout + build.stderr)

    def run_case(self, mode):
        result = subprocess.run([str(self.binary), mode], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rollover_closes_the_explorer_and_preserves_canvas_loading(self):
        self.run_case("explorer")

    def test_rollover_closes_questions_and_retains_the_draft(self):
        self.run_case("questions")


if __name__ == "__main__":
    unittest.main()
