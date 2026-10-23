#!/usr/bin/env python3
"""Exercise timed pass expiry callbacks without a signed Screen Time device."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("swift"), "Swift is required")
class TimedAccessCallbackContractTests(unittest.TestCase):
    def test_old_callbacks_cannot_spend_passes_and_expiry_reconciles(self):
        shared_source = (ROOT / "Shared/ShieldRebuildHelper.swift").read_text()
        session = shared_source[shared_source.index("struct UsageBudgetSession:"):
                                shared_source.index("// MARK: - Shield Rebuild")]
        predicates = shared_source[shared_source.index("    private static func coercedDate"):
                                   shared_source.index("    /// Resolve only current timed-pass activities.")]
        monitor_source = (ROOT / "DeviceActivityMonitor/DeviceActivityMonitorExtension.swift").read_text()
        monitor = monitor_source[monitor_source.index("    private func handleMinuteEvent"):
                                monitor_source.index("    private func reloadWidgets")]
        source = r'''
import Foundation
struct DeviceActivityEvent { struct Name { let rawValue: String; init(_ s: String) { rawValue = s } } }
struct DeviceActivityName: Equatable {
    let rawValue: String
    init(_ s: String) { rawValue = s }
}
struct DeviceActivityCenter { func stopMonitoring(_ names: [DeviceActivityName]) {} }
struct WidgetCenter { static let shared = WidgetCenter(); func reloadAllTimelines() {} }
enum MonitorLogger {
    static func info(_ s: String) {}
    static func error(_ s: String) { fatalError(s) }
}
func appendMonitorLog(_ s: String) {}
enum SharedKeys {
    static let suite = "TimedAccessCallbackContract." + UUID().uuidString
    static let defaults = UserDefaults(suiteName: suite)!
    static func appGroupDefaults() -> UserDefaults { defaults }
    static func usageBudgetKey(_ s: String) -> String { "budget_" + s }
    static func usageBudgetExpiryKey(_ s: String) -> String { "expiry_" + s }
    static func usageBudgetStartedKey(_ s: String) -> String { "started_" + s }
    static func usageBudgetInitialKey(_ s: String) -> String { "initial_" + s }
}
''' + session + r'''
enum ShieldRebuildHelper {
    struct Group { let active = true; let id = "G"; let name = "Review" }
    static func loadGroups(defaults: UserDefaults) -> [Group] { [Group()] }
    static func cachedSelection(for id: String, data: Data) -> FamilyActivitySelection? {
        FamilyActivitySelection()
    }
    static func withUsageBudgetLock<T>(_ body: () throws -> T) rethrows -> T { try body() }
''' + predicates + r'''
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
let now = Date.now
var active = UsageBudgetSession(minutes: 10, startedAt: now,
                                expiresAt: now.addingTimeInterval(900))
active.save(to: defaults, groupId: "G")
for callback in ["usageBudgetTick_G_30", "usageBudgetDone_G", "timedAccess_tick"] {
    monitor.dispatch(callback)
    assert(UsageBudgetSession.load(from: defaults, groupId: "G") == active,
           "A stale or threshold callback must leave an active timed pass alone")
    assert(monitor.rebuilds == 0)
}
active.expiresAt = now.addingTimeInterval(-1)
active.save(to: defaults, groupId: "G")
monitor.dispatch("timedAccess_end")
assert(UsageBudgetSession.load(from: defaults, groupId: "G") == nil,
       "Expiry callback must clear the timed pass")
assert(defaults.object(forKey: SharedKeys.usageBudgetKey("G")) == nil,
       "Expiry callback must clear widget compatibility data")
assert(monitor.rebuilds == 1, "Expiry callback must rebuild shields")
// An old balance without the new pass record never grants access.
defaults.set(60, forKey: SharedKeys.usageBudgetKey("G"))
defaults.set(now.addingTimeInterval(600), forKey: SharedKeys.usageBudgetExpiryKey("G"))
assert(ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: "G", at: now) == 0)
monitor.dispatch("usageBudgetDone_G")
assert(ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: "G", at: now) == 0,
       "Legacy-only balance must never grant access")
print("PASS: timed access callbacks only reconcile the saved deadline")
'''
        with tempfile.TemporaryDirectory(prefix="nowhere-timed-access-contract-") as directory:
            script = Path(directory) / "main.swift"
            script.write_text(source)
            result = subprocess.run(["swift", str(script)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS:", result.stdout)


if __name__ == "__main__":
    unittest.main()
