#!/usr/bin/env python3
"""Execute the real app-hosted widget purchase entry around a delayed system authorization."""
from pathlib import Path
import os
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
class WidgetAccountAuthorizationTests(unittest.TestCase):
    def test_root_deeplink_authorization_cannot_charge_incoming_account_or_reset_its_purchase(self):
        with tempfile.TemporaryDirectory(prefix="nowhere-root-widget-account-") as directory:
            folder = Path(directory)
            root_source = Path(os.environ.get("NOWHERE_ROOT_AUTHORIZATION_SOURCE", ROOT / "Nowhere/NowhereApp.swift")).read_text()
            method = declaration(root_source, "private func processPendingWidgetUnlock()")
            # SwiftUI State is a reference boundary; the fixture uses a class.
            # An explicit self capture adapts that boundary without changing logic.
            method = method.replace("Task { @MainActor in", "Task { @MainActor [self] in")
            model = (ROOT / "Nowhere/AppModel.swift").read_text()
            common = (ROOT / "Scripts/Fixtures/WidgetAccountAuthorizationHarness.swift").read_text().split("struct UnlockGroupWidgetIntent", 1)[0]
            common = common.replace("var historyWorkGeneration = UUID()", "var didCompleteBootstrap = true\n    var historyWorkGeneration = UUID()")
            common = common.replace("/*__CURRENT__*/", declaration(model, "func isHistoryWorkCurrent("))
            reset = declaration((ROOT / "Nowhere/NowhereApp.swift").read_text(), "private func resetWidgetUnlockProcessing()")
            harness = common + (ROOT / "Scripts/Fixtures/RootWidgetAccountAuthorizationHarness.swift").read_text().replace("/*__ROOT__*/", method).replace("/*__RESET__*/", reset)
            script = folder / "Harness.swift"
            script.write_text(harness)
            binary = folder / "root-widget"
            build = subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(folder / "modules"), str(script), "-o", str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_delayed_authorization_cannot_charge_the_incoming_account(self):
        self.run_intent_case("account-switch")

    def test_active_pass_rejects_repeat_purchase_without_charging(self):
        self.run_intent_case("active-pass")

    def run_intent_case(self, mode):
        with tempfile.TemporaryDirectory(prefix="nowhere-widget-account-") as directory:
            folder = Path(directory)
            intent_path = Path(os.environ.get("NOWHERE_WIDGET_INTENT_SOURCE", ROOT / "UnlockWidget/UnlockGroupWidgetIntent.swift"))
            intent = intent_path.read_text().split("struct UnlockGroupWidgetIntent:", 1)[1]
            model = (ROOT / "Nowhere/AppModel.swift").read_text()
            harness = (ROOT / "Scripts/Fixtures/WidgetAccountAuthorizationHarness.swift").read_text()
            harness = harness.replace("/*__PERFORM__*/", "@MainActor\n" + declaration(intent, "func perform()"))
            harness = harness.replace("/*__CURRENT__*/", declaration(model, "func isHistoryWorkCurrent("))
            swift = folder / "main.swift"
            swift.write_text(harness)
            binary = folder / "widget-account"
            build = subprocess.run(["swiftc", "-D", "NOWHERE_APP", "-parse-as-library", "-module-cache-path", str(folder / "modules"), str(swift), "-o", str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(binary), mode], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
