#!/usr/bin/env python3
"""Compile production economy/file persistence with synthetic isolated dependencies."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class EconomyWriteBarrierTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="nowhere-economy-barrier-")
        cls.addClassCleanup(cls.directory.cleanup)
        folder = Path(cls.directory.name)
        cls.binary = folder / "barrier"
        result = subprocess.run([
            "swiftc", "-parse-as-library", "-module-cache-path", str(folder / "modules"),
            str(ROOT / "Nowhere/Services/PersistenceManager.swift"),
            str(ROOT / "Nowhere/Stores/UserEconomyStore.swift"),
            str(ROOT / "Scripts/Fixtures/EconomyWriteBarrierHarness.swift"),
            "-o", str(cls.binary),
        ], capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def run_case(self, mode):
        result = subprocess.run([str(self.binary), mode], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_cancelled_file_write_does_not_persist_or_report_an_error(self):
        self.run_case("cancelled")

    def test_cancellation_after_encoding_stops_the_imminent_write(self):
        self.run_case("encodingCancellation")

    def test_failed_outgoing_flush_aborts_rotation_and_can_retry(self):
        self.run_case("flushFailure")

    def test_suspended_old_writers_cannot_replace_incoming_account_history(self):
        self.run_case("barrier")


if __name__ == "__main__":
    unittest.main()
