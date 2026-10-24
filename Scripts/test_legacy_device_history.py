#!/usr/bin/env python3
"""Exercise production local-only legacy projection with immutable synthetic archives."""
from pathlib import Path
import shutil
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class LegacyDeviceHistoryTests(unittest.TestCase):
    def test_production_defaults_scope_rotates_paid_passes_and_freshness_but_preserves_device_fence(self):
        with tempfile.TemporaryDirectory(prefix="nowhere-account-scope-") as directory:
            folder = Path(directory)
            storage = (ROOT / "Nowhere/Services/AccountHistoryStorage.swift").read_text()
            shared = (ROOT / "Nowhere/Utilities/SharedKeys.swift").read_text()
            names = set(re.findall(r"SharedKeys\.(\w+)", storage))
            constants = [re.search(r"    static let " + name + r"\s*=\s*(.+)", shared).group(0) for name in sorted(names)]
            constants += [re.search(r"    static func " + name + r"\([^\n]+", shared).group(0) for name in ["usageBudgetKey", "usageBudgetInitialKey", "usageBudgetStartedKey", "usageBudgetExpiryKey"]]
            support = "import Foundation\nenum SharedKeys {\n" + "\n".join(constants) + "\n}\n"
            support += 'enum SupabaseSyncService { static let retryQueueKey = "supabaseRetryQueue_v1"; static let optionEntryIntentKey = "supabaseOptionEntryIntents_v1" }\n'
            support += 'extension UserDefaults { static func nowhere() -> UserDefaults { .standard } }\n'
            budget = (ROOT / "Shared/ShieldRebuildHelper.swift").read_text()
            support += budget[budget.index("struct UsageBudgetSession:"):budget.index("/// Device-level fence")]
            platform = folder / "Platform.swift"
            platform.write_text(support)
            binary = folder / "scope"
            build = subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(folder / "modules"),
                str(platform), str(ROOT / "Nowhere/Services/AccountHistoryVault.swift"),
                str(ROOT / "Nowhere/Services/AccountHistoryStorage.swift"),
                str(ROOT / "Scripts/Fixtures/AccountHistoryStorageHarness.swift"), "-o", str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

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
