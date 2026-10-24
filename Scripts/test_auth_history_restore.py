#!/usr/bin/env python3
"""Run the actual auth initial-restore method with a failing local history boundary."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class AuthHistoryRestoreTests(unittest.TestCase):
    def test_storage_failure_retains_valid_credentials_without_signup_or_optimistic_publish(self):
        source = Path(os.environ.get("NOWHERE_AUTH_RESTORE_SOURCE", ROOT / "Nowhere/Services/AuthenticationService.swift")).read_text()
        start = source.index("    private func loadStoredSessionAndRefreshUser()")
        end = source.index("    /// Single source of truth", start)
        method = source[start:end]
        fixture = (ROOT / "Scripts/Fixtures/AuthHistoryRestoreHarness.swift").read_text().replace("// INSERT_RESTORE", method)
        with tempfile.TemporaryDirectory(prefix="nowhere-auth-history-") as directory:
            folder = Path(directory)
            script = folder / "Harness.swift"
            script.write_text(fixture)
            binary = folder / "auth-history"
            build = subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(folder / "modules"), str(script), "-o", str(binary)], capture_output=True, text=True, timeout=45)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("PASS", run.stdout)

if __name__ == "__main__":
    unittest.main()
