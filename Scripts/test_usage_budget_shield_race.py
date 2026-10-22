#!/usr/bin/env python3
"""Execute production shield rebuild against recording framework boundaries."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class UsageBudgetShieldRaceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="nowhere-shield-contract-")
        cls.addClassCleanup(cls.directory.cleanup)
        folder = Path(cls.directory.name)
        shared = (ROOT / "Shared/ShieldRebuildHelper.swift").read_text()
        models = shared[shared.index("enum UsageBudgetThresholdResult:"):shared.index("// MARK: - Shield Rebuild")]
        predicates = shared[shared.index("    private static func coercedDate"):shared.index("    // MARK: - Public")]
        start = predicates.index("    static func usageSelectionMatches")
        end = predicates.index("    /// Resolve callbacks", start)
        predicates = predicates[:start] + "    static func usageSelectionMatches(defaults: UserDefaults, groupId: String, session: UsageBudgetSession) -> Bool { true }\n" + predicates[end:]
        rebuild = shared[shared.index("    static func rebuild("):shared.index("    // MARK: - Usage Budget Schedule")]
        rebuild = rebuild.replace("        #if canImport(ManagedSettings) && canImport(FamilyControls)\n", "").replace("        #endif\n", "")
        source = (ROOT / "Scripts/Fixtures/UsageBudgetShieldHarness.swift").read_text()
        for key, value in [("MODELS", models), ("PREDICATES", predicates), ("REBUILD", rebuild)]:
            source = source.replace("/*__" + key + "__*/", value)
        script = folder / "main.swift"
        script.write_text(source)
        cls.binary = folder / "shield-contract"
        build = subprocess.run(["swiftc", "-module-cache-path", str(folder / "modules"), str(script), "-o", str(cls.binary)], capture_output=True, text=True, timeout=45)
        if build.returncode:
            raise AssertionError(build.stdout + build.stderr)

    def run_case(self, mode):
        result = subprocess.run([str(self.binary), self.directory.name, mode], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS:", result.stdout)

    def test_every_shield_writer_uses_the_shared_rebuild(self):
        for relative in ["Nowhere/Stores/BlockingStore.swift",
                         "DeviceActivityMonitor/DeviceActivityMonitorExtension.swift"]:
            source = (ROOT / relative).read_text()
            self.assertNotRegex(source, r"\.shield\.(applications|applicationCategories)\s*=", relative)
            self.assertIn("ShieldRebuildHelper.rebuild(", source, relative)

    def test_shield_snapshot_and_assignment_share_the_budget_commit_lock(self):
        self.run_case("race")

    def test_paid_apps_override_overlapping_groups_and_reshield_when_paused(self):
        self.run_case("overlap")

    def test_paid_apps_are_exceptions_to_blocked_categories(self):
        self.run_case("category-exception")

    def test_paid_categories_override_duplicate_category_blockers(self):
        self.run_case("paid-category")

    def test_paused_and_expired_budgets_do_not_exempt_apps(self):
        for mode in ["paused", "expired"]:
            with self.subTest(mode=mode):
                self.run_case(mode)


if __name__ == "__main__":
    unittest.main()
