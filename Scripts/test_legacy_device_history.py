#!/usr/bin/env python3
"""Exercise production local-only legacy projection with immutable synthetic archives."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class LegacyDeviceHistoryTests(unittest.TestCase):
    def test_legacy_sources_stay_readable_without_exposing_or_mutating_owned_accounts(self):
        with tempfile.TemporaryDirectory(prefix="nowhere-legacy-history-") as directory:
            folder = Path(directory)
            binary = folder / "history"
            build = subprocess.run([
                "swiftc", "-parse-as-library", "-module-cache-path", str(folder / "modules"),
                str(ROOT / "Nowhere/Services/AccountHistoryVault.swift"),
                str(ROOT / "Nowhere/Models/PastDaySnapshot.swift"),
                str(ROOT / "Nowhere/Models/LegacyDeviceHistory.swift"),
                str(ROOT / "Scripts/Fixtures/LegacyDeviceHistoryHarness.swift"), "-o", str(binary),
            ], capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
