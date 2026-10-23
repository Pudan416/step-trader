#!/usr/bin/env python3
"""Execute Gallery's real persistence callbacks with the production epoch barrier."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]

@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class GalleryAccountEpochTests(unittest.TestCase):
    def test_old_view_callback_starting_after_new_account_cannot_persist_or_upload(self):
        source = Path(os.environ.get("NOWHERE_GALLERY_SOURCE", ROOT / "Nowhere/Views/GalleryView.swift")).read_text()
        def extract(start, end):
            a = source.index(start)
            return source[a:source.index(end, a)]
        save = extract("    @discardableResult\n    private func saveCanvasLocally()", "    private func publishCanvasPersistence")
        publish = extract("    private func publishCanvasPersistence", "    @discardableResult\n    private func addAndSpawnHappening")
        widget = extract("    @MainActor\n    private func refreshWidgetSnapshot()", "    private func syncCanvasWithModel")
        current = extract("    private var hasCurrentCanvasEpoch", "    @State private var canvasLoaded") if "private var hasCurrentCanvasEpoch" in source else ""
        storage = (ROOT / "Nowhere/Services/CanvasStorageService.swift").read_text()
        barrier = storage[storage.index("struct CanvasStorageWriteEpoch"):storage.index("// MARK: - Canvas Storage Service")]
        fixture = (ROOT / "Scripts/Fixtures/GalleryAccountEpochHarness.swift").read_text()
        for name, text in [("BARRIER", barrier), ("CURRENT", current), ("SAVE", save), ("PUBLISH", publish), ("WIDGET", widget)]:
            fixture = fixture.replace("// INSERT_" + name, text)
        with tempfile.TemporaryDirectory(prefix="nowhere-gallery-account-") as directory:
            folder = Path(directory)
            script = folder / "Harness.swift"
            script.write_text(fixture)
            binary = folder / "gallery"
            build = subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(folder / "modules"), str(script), "-o", str(binary)], capture_output=True, text=True, timeout=45)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("PASS", run.stdout)

if __name__ == "__main__":
    unittest.main()
