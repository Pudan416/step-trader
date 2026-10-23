#!/usr/bin/env python3
"""Exercise timed access purchases with a deterministic Screen Time daemon stub."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class TimedAccessPassTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="nowhere-recovery-contract-")
        cls.addClassCleanup(cls.directory.cleanup)
        source = (ROOT / "Shared/ShieldRebuildHelper.swift").read_text()
        model = source[source.index("struct UsageBudgetSession:"):
                       source.index("// MARK: - Shield Rebuild")]
        transactions = source[source.index("    private struct PreparedUsageBudgetRegistration"):
                              source.index("    // MARK: - Pending Widget Pass Monitoring")]
        transactions = transactions.removesuffix("\n").removesuffix("\n")
        transactions = transactions.rsplit("    #endif", 1)[0]
        predicates = source[source.index("    private static func coercedDate"):
                            source.index("    static func usageSelectionMatches")]
        harness = (ROOT / "Scripts/Fixtures/UsageBudgetRecoveryHarness.swift").read_text()
        harness = harness.replace("// INSERT_MODEL", model)
        harness = harness.replace("// INSERT_PREDICATES", predicates)
        harness = harness.replace("// INSERT_TRANSACTIONS", transactions)
        script = Path(cls.directory.name) / "main.swift"
        script.write_text(harness)
        cls.binary = Path(cls.directory.name) / "recovery-tests"
        result = subprocess.run(["swiftc", str(script), "-o", str(cls.binary)],
                                capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def test_budget_transactions(self):
        for scenario in ["purchase_starts_deadline", "active_purchase_rejected",
                         "recovery_keeps_deadline", "failed_purchase_rolls_back",
                         "expired_purchase_can_restart"]:
            with self.subTest(scenario=scenario):
                result = subprocess.run([str(self.binary), scenario],
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()
