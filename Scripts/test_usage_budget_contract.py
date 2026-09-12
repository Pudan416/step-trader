#!/usr/bin/env python3
"""Exercise actual extension callback bodies without a signed Screen Time device.

Only framework side effects are replaced with recording stubs. The shared budget
predicate and extension handlers are extracted from production on every run, so
this protects the cross-target path that the app's XCTest bundle cannot import.
Run on a Mac with Swift: python3 Scripts/test_usage_budget_contract.py
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("swift"), "Swift is required")
class UsageBudgetCallbackContractTests(unittest.TestCase):
    def test_expired_and_stale_callbacks_reconcile_the_saved_window(self):
        shared = (ROOT / "Shared/ShieldRebuildHelper.swift").read_text()
        shared = shared[shared.index("    private static func coercedDate"):
                        shared.index("    // MARK: - Public")]
        monitor = (ROOT / "DeviceActivityMonitor/DeviceActivityMonitorExtension.swift").read_text()
        monitor = monitor[monitor.index("    private func handleMinuteEvent"):
                          monitor.index("    private func reloadWidgets")]
        source = r'''
import Foundation
struct DeviceActivityEvent { struct Name { let rawValue: String; init(_ s: String) { rawValue = s } } }
struct DeviceActivityName { init(_ s: String) {} }
struct DeviceActivityCenter { func stopMonitoring(_ names: [DeviceActivityName]) {} }
enum MonitorLogger { static func info(_ s: String) {} }
func appendMonitorLog(_ s: String) {}
enum SharedKeys {
    static let suite = "UsageBudgetCallbackContract." + UUID().uuidString
    static let defaults = UserDefaults(suiteName: suite)!
    static func appGroupDefaults() -> UserDefaults { defaults }
    static func usageBudgetKey(_ s: String) -> String { "budget_" + s }
    static func usageBudgetExpiryKey(_ s: String) -> String { "expiry_" + s }
    static func usageBudgetStartedKey(_ s: String) -> String { "started_" + s }
    static func usageBudgetInitialKey(_ s: String) -> String { "initial_" + s }
}
enum ShieldRebuildHelper {
    struct Group { let active = true; let id = "G"; let name = "Review" }
    static func loadGroups(defaults: UserDefaults) -> [Group] { [Group()] }
''' + shared + r'''
}
final class MonitorHarness {
    var rebuilds = 0
    func rebuildBlockFromExtension() { rebuilds += 1 }
    func reloadWidgets() {}
    func startPendingWidgetBudgets() {}
    func dispatch(_ s: String) { handleMinuteEvent(DeviceActivityEvent.Name(s)) }
''' + monitor + r'''
}
let defaults = SharedKeys.defaults
defer { defaults.removePersistentDomain(forName: SharedKeys.suite) }
let monitor = MonitorHarness()
let now = Date()
defaults.set(60, forKey: SharedKeys.usageBudgetKey("G"))
defaults.set(now.addingTimeInterval(15 * 60), forKey: SharedKeys.usageBudgetExpiryKey("G"))
assert(ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: "G", at: now) == 15)
for callback in ["usageBudgetTick_G_30", "usageBudgetWidgetTick_G_45", "usageBudgetDone_G"] {
    monitor.dispatch(callback)
    assert(defaults.integer(forKey: SharedKeys.usageBudgetKey("G")) == 60,
           "Legacy callback must not consume a newer wall-clock purchase: " + callback)
    assert(monitor.rebuilds == 0)
}
for callback in ["usageBudgetTick_G_2", "usageBudgetWidgetTick_G_5", "usageBudgetDone_G", "ticketGroup_G"] {
    defaults.set(60, forKey: SharedKeys.usageBudgetKey("G"))
    defaults.set(now.addingTimeInterval(-600), forKey: SharedKeys.usageBudgetExpiryKey("G"))
    let previous = monitor.rebuilds
    monitor.dispatch(callback)
    assert(defaults.integer(forKey: SharedKeys.usageBudgetKey("G")) == 0,
           "Expired callback must clear the window: " + callback)
    assert(monitor.rebuilds == previous + 1, "Expired callback must rebuild the shield")
}
print("PASS: all legacy callbacks preserve active windows and re-shield expired windows")
'''
        with tempfile.TemporaryDirectory(prefix="nowhere-budget-contract-") as directory:
            script = Path(directory) / "main.swift"
            script.write_text(source)
            result = subprocess.run(["swift", str(script)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS:", result.stdout)


if __name__ == "__main__":
    unittest.main()
