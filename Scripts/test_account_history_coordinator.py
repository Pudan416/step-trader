#!/usr/bin/env python3
"""Execute the production coordinator and vault against synthetic platform boundaries."""
from pathlib import Path
import shutil
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class AccountHistoryCoordinatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="nowhere-account-coordinator-")
        cls.addClassCleanup(cls.directory.cleanup)
        folder = Path(cls.directory.name)
        coordinator_path = Path(os.environ.get("NOWHERE_COORDINATOR_SOURCE", ROOT / "Nowhere/Services/AccountHistoryCoordinator.swift"))
        coordinator = coordinator_path.read_text().replace("import DeviceActivity\n", "")
        shared = (ROOT / "Shared/ShieldRebuildHelper.swift").read_text()
        models = shared[shared.index("struct UsageBudgetSession:"):shared.index("/// A small `flock` wrapper")]
        source = (ROOT / "Scripts/Fixtures/AccountHistoryCoordinatorHarness.swift").read_text()
        app_model = Path(os.environ.get("NOWHERE_RESTART_SOURCE", ROOT / "Nowhere/AppModel.swift")).read_text()
        restart = app_model[app_model.index("    func restartAccountHistoryWork()"):app_model.index("    /// Reuse the local loaders")]
        source = source.replace("// INSERT_COORDINATOR", coordinator).replace("// INSERT_BUDGET_MODELS", models).replace("// INSERT_RESTART", restart)
        script = folder / "Harness.swift"
        script.write_text(source)
        cls.binary = folder / "coordinator"
        build = subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(folder / "modules"),
            str(ROOT / "Nowhere/Services/AccountHistoryVault.swift"), str(script), "-o", str(cls.binary)],
            capture_output=True, text=True, timeout=60)
        if build.returncode:
            raise AssertionError(build.stdout + build.stderr)

    def test_account_transitions(self):
        for mode in ["widget-refresh", "roundtrip", "generation-reject", "commit-failure", "constructor-failure", "cache-failure", "restore-failure", "queued"]:
            with self.subTest(mode=mode):
                run = subprocess.run([str(self.binary), mode], capture_output=True, text=True, timeout=15)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                self.assertIn("PASS", run.stdout)

if __name__ == "__main__":
    unittest.main()
