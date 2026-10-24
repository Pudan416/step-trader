#!/usr/bin/env python3
"""Execute the production AppModel work-admission and drain methods with controlled continuations."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end].removeprefix("private ")


@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class AccountModelWorkTests(unittest.TestCase):
    def test_old_producers_and_loaders_drain_before_resume(self):
        with tempfile.TemporaryDirectory(prefix="nowhere-model-work-") as directory:
            folder = Path(directory)
            source = (ROOT / "Nowhere/AppModel.swift").read_text()
            harness = (ROOT / "Scripts/Fixtures/AccountModelWorkHarness.swift").read_text()
            for key, marker in [
                ("SCHEDULE", "func scheduleHistoryWork("),
                ("SUSPEND", "func suspendHistoryWork()"),
                ("RESUME", "func resumeHistoryWork()"),
                ("CURRENT", "func isHistoryWorkCurrent("),
                ("WAIT", "private func waitForHistoryWorkResumption()"),
            ]:
                harness = harness.replace("/*__" + key + "__*/", declaration(source, marker))
            blocking = (ROOT / "Nowhere/Stores/BlockingStore.swift").read_text()
            for key, marker in [
                ("BLOCKING_SUSPEND", "func suspendPersistence()"),
                ("BLOCKING_RESUME", "func resumePersistence()"),
                ("BLOCKING_SAVE", "private func saveAppSelection()"),
            ]:
                harness = harness.replace("/*__" + key + "__*/", declaration(blocking, marker))
            swift = folder / "main.swift"
            swift.write_text(harness)
            binary = folder / "model-work"
            build = subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(folder / "modules"), str(swift), "-o", str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
