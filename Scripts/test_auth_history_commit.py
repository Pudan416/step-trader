#!/usr/bin/env python3
"""Execute actual auth commit/signout/store methods around a controlled history I/O boundary."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]

@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class AuthHistoryCommitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="nowhere-auth-commit-")
        cls.addClassCleanup(cls.directory.cleanup)
        folder = Path(cls.directory.name)
        source = Path(os.environ.get("NOWHERE_AUTH_COMMIT_SOURCE", ROOT / "Nowhere/Services/AuthenticationService.swift")).read_text()
        def method(name):
            start = source.rfind("\n", 0, source.index("func " + name + "(")) + 1
            body = source.index("{", start)
            depth = 1
            end = body + 1
            while depth:
                depth += (source[end] == "{") - (source[end] == "}")
                end += 1
            return source[start:end]
        methods = "\n".join(method(name) for name in ["checkSessionGeneration", "advanceSessionGeneration", "commitAccountSession", "queueSignedOutHistoryTransition", "signOut", "storeSession", "clearStoredSession"])
        fixture = (ROOT / "Scripts/Fixtures/AuthHistoryCommitHarness.swift").read_text().replace("// INSERT_METHODS", methods)
        script = folder / "Harness.swift"
        script.write_text(fixture)
        cls.binary = folder / "auth-commit"
        build = subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(folder / "modules"), str(script), "-o", str(cls.binary)], capture_output=True, text=True, timeout=45)
        if build.returncode:
            raise AssertionError(build.stdout + build.stderr)

    def test_auth_history_boundary(self):
        modes = os.environ.get("NOWHERE_AUTH_COMMIT_CASES", "before-model,prepare-failure,signout-before-model,signout-during-prepare").split(",")
        for mode in modes:
            with self.subTest(mode=mode):
                run = subprocess.run([str(self.binary), mode], capture_output=True, text=True, timeout=15)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                self.assertIn("PASS", run.stdout)

if __name__ == "__main__":
    unittest.main()
