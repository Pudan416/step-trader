#!/usr/bin/env python3
"""Run the actual Foundation history vault with isolated, nonpersonal fixtures."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class AccountHistoryVaultTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="nowhere-account-vault-")
        cls.addClassCleanup(cls.directory.cleanup)
        folder = Path(cls.directory.name)
        cls.binary = folder / "vault"
        build = subprocess.run([
            "swiftc", "-parse-as-library", "-module-cache-path", str(folder / "modules"),
            str(ROOT / "Nowhere/Services/AccountHistoryVault.swift"),
            str(ROOT / "Scripts/Fixtures/AccountHistoryVaultHarness.swift"),
            "-o", str(cls.binary),
        ], capture_output=True, text=True, timeout=60)
        if build.returncode:
            raise AssertionError(build.stdout + build.stderr)

    def run_case(self, mode):
        result = subprocess.run([str(self.binary), mode], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_legacy_history_is_quarantined_without_reassigning_ids(self):
        self.run_case("legacy")

    def test_a_b_a_b_preserves_history_queues_and_restore_flags(self):
        self.run_case("roundtrip")

    def test_corrupt_incoming_archive_preserves_active_account(self):
        self.run_case("corruption")

    def test_malformed_file_directory_paths_fail_before_mutation(self):
        self.run_case("malformedPath")

    def test_symlinks_and_overlapping_roots_fail_closed(self):
        self.run_case("symlinks")

    def test_redirected_archive_files_root_cannot_restore_or_display_foreign_bytes(self):
        self.run_case("archiveRootSymlink")

    def test_disk_write_failure_rolls_back_and_remains_retryable(self):
        self.run_case("writeFailure")

    def test_restart_recovers_interrupted_switch(self):
        self.run_case("interrupted")


if __name__ == "__main__":
    unittest.main()
