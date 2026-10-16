#!/usr/bin/env python3
"""Run the production shield rebuild against a paused ManagedSettings writer.

The deterministic ordering reproduces an extension capturing an inactive budget
before a purchase commits, then applying that obsolete shield afterward. Framework
effects use recording substitutes; the rebuild, predicates and file locks come
from production. This checks ordering, not Screen Time enforcement on a phone.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("swift"), "Swift is required")
class UsageBudgetShieldRaceTests(unittest.TestCase):
    def test_every_shield_writer_uses_the_shared_rebuild(self):
        for relative in ["Nowhere/Stores/BlockingStore.swift",
                         "DeviceActivityMonitor/DeviceActivityMonitorExtension.swift"]:
            source = (ROOT / relative).read_text()
            self.assertNotRegex(source, r"\.shield\.(applications|applicationCategories)\s*=", relative)
            self.assertIn("ShieldRebuildHelper.rebuild(", source, relative)

    def test_shield_snapshot_and_assignment_share_the_budget_commit_lock(self):
        shared = (ROOT / "Shared/ShieldRebuildHelper.swift").read_text()
        models = shared[shared.index("enum UsageBudgetThresholdResult:"):
                        shared.index("// MARK: - Shield Rebuild")]
        predicates = shared[shared.index("    private static func coercedDate"):
                            shared.index("    // MARK: - Public")]
        # Selection identity is covered by the existing recovery contract. The
        # race fixture holds the selected token constant across both processes.
        start = predicates.index("    static func usageSelectionMatches")
        end = predicates.index("    /// Resolve callbacks", start)
        predicates = predicates[:start] + """
    static func usageSelectionMatches(defaults: UserDefaults, groupId: String,
                                      session: UsageBudgetSession) -> Bool { true }
""" + predicates[end:]
        rebuild = shared[shared.index("    static func rebuild("):
                         shared.index("    // MARK: - Usage Budget Schedule")]
        rebuild = rebuild.replace("        #if canImport(ManagedSettings) && canImport(FamilyControls)\n", "")
        rebuild = rebuild.replace("        #endif\n", "")
        source = r'''
import Foundation
import Darwin
typealias ApplicationToken = Int
typealias ActivityCategoryToken = Int
struct FamilyActivitySelection: Codable {
    var applicationTokens: Set<Int> = [7]
    var categoryTokens: Set<Int> = []
}
struct GroupTuple { let id = "G"; let active = true; let selectionData: Data? }
struct StoredUnlockSettings: Codable { let familyControlsModeEnabled: Bool }
enum SharedKeys {
    static let appGroupId = "ShieldRace." + UUID().uuidString
    static let appUnlockSettings = "settings"
    static let shieldState = "shieldState"
    static let defaults = UserDefaults(suiteName: appGroupId)!
    static func usageBudgetKey(_ s: String) -> String { "budget_" + s }
    static func usageBudgetExpiryKey(_ s: String) -> String { "expiry_" + s }
    static func usageBudgetStartedKey(_ s: String) -> String { "started_" + s }
    static func usageBudgetInitialKey(_ s: String) -> String { "initial_" + s }
    static func timeAccessSelectionKey(_ s: String) -> String { "selection_" + s }
}
struct Logger {
    init(subsystem: String, category: String) {}
    func error(_ message: String) { print(message) }
}
final class ShieldStub {
    private let lock = NSLock()
    private var storedApplications: Set<Int>?
    var beforeWrite: ((Set<Int>?) -> Void)?
    var applications: Set<Int>? {
        get { lock.lock(); defer { lock.unlock() }; return storedApplications }
        set {
            beforeWrite?(newValue)
            lock.lock(); defer { lock.unlock() }; storedApplications = newValue
        }
    }
    enum Categories { case specific(Set<Int>) }
    var applicationCategories: Categories?
}
struct ManagedSettingsStore {
    struct Name { init(_ s: String) {} }
    static let state = ShieldStub()
    init(named: Name) {}
    var shield: ShieldStub { Self.state }
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let stateLock = UsageBudgetFileLock(fileURL: directory.appendingPathComponent("state.lock"))
let registrationLock = UsageBudgetFileLock(fileURL: directory.appendingPathComponent("registration.lock"))
''' + models + r'''
enum ShieldRebuildHelper {
    static func withUsageBudgetLock<T>(_ body: () throws -> T) throws -> T {
        try stateLock.withLock(body)
    }
    static func loadGroups(defaults: UserDefaults) -> [GroupTuple] {
        [GroupTuple(selectionData: try! JSONEncoder().encode(FamilyActivitySelection()))]
    }
    static func cachedSelection(for id: String, data: Data) -> FamilyActivitySelection? {
        try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }
    static func startPendingWidgetBudgets(defaults: UserDefaults, groups: [GroupTuple]) {
        // A daemon registration may need this lock. Pending work must run after
        // rebuild releases it, otherwise the app deadlocks itself.
        try! withUsageBudgetLock { defaults.synchronize() }
    }
    static func logDiagnostic(defaults: UserDefaults, apps: Int, categories: Int,
                              budgetApps: Int, budgetAppsStillShielded: Int) {}
''' + predicates + rebuild + r'''
}
let defaults = SharedKeys.defaults
defer { defaults.removePersistentDomain(forName: SharedKeys.appGroupId) }
var initial = UsageBudgetSession(minutes: 10, startedAt: Date(), expiresAt: Date().addingTimeInterval(3600))
initial.monitoringFailed = true
initial.save(to: defaults, groupId: "G")
defaults.synchronize()
let writerPaused = DispatchSemaphore(value: 0)
let resumeWriter = DispatchSemaphore(value: 0)
let staleWriterDone = DispatchSemaphore(value: 0)
let purchaseDone = DispatchSemaphore(value: 0)
ManagedSettingsStore.state.beforeWrite = { applications in
    if applications == [7] {
        writerPaused.signal()
        assert(resumeWriter.wait(timeout: .now() + 5) == .success)
    }
}
DispatchQueue.global().async {
    ShieldRebuildHelper.rebuild(startPendingBudgets: false)
    staleWriterDone.signal()
}
assert(writerPaused.wait(timeout: .now() + 5) == .success)
// Probe lock ownership at the exact framework assignment boundary. No timing
// assumption is needed to distinguish the old unlocked writer from the fix.
let descriptor = open(stateLock.fileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
assert(descriptor >= 0)
let unprotected = flock(descriptor, LOCK_EX | LOCK_NB) == 0
if unprotected { flock(descriptor, LOCK_UN) }
close(descriptor)
func commitPurchaseAndRebuild() {
    try! stateLock.withLock {
        defaults.synchronize()
        var committed = UsageBudgetSession.load(from: defaults, groupId: "G")!
        committed.monitoringFailed = false
        committed.save(to: defaults, groupId: "G")
        defaults.synchronize()
    }
    ShieldRebuildHelper.rebuild()
}
if unprotected {
    // Old writer permits the whole purchase to complete before its stale set
    // lands. This reproduces the reported purchased-but-still-shielded state.
    commitPurchaseAndRebuild()
    resumeWriter.signal()
    assert(staleWriterDone.wait(timeout: .now() + 5) == .success)
} else {
    // The new writer holds the commit lock until assignment completes. A later
    // purchase therefore computes and applies the final authoritative set.
    DispatchQueue.global().async {
        commitPurchaseAndRebuild()
        purchaseDone.signal()
    }
    resumeWriter.signal()
    assert(staleWriterDone.wait(timeout: .now() + 5) == .success)
    assert(purchaseDone.wait(timeout: .now() + 5) == .success)
}
assert(ManagedSettingsStore.state.applications == nil,
       "Obsolete extension shield landed after purchase commit")
assert(!unprotected, "Shield snapshot and assignment must hold the purchase state lock")
ManagedSettingsStore.state.beforeWrite = nil
// startMonitoring can deliver a synchronous callback. The coordinator must
// release the state lock before that callback rebuilds the shield.
try! UsageBudgetRegistrationCoordinator.perform(
    stateLock: stateLock, registrationLock: registrationLock,
    prepare: { 1 },
    register: { _ in ShieldRebuildHelper.rebuild(startPendingBudgets: false) },
    commit: { _ in }, rollback: { _ in })
print("PASS: obsolete shield cannot overwrite purchase; callbacks and pending registration do not deadlock")
'''
        with tempfile.TemporaryDirectory(prefix="nowhere-shield-race-") as directory:
            script = Path(directory) / "main.swift"
            script.write_text(source)
            result = subprocess.run(["swift", str(script), directory], capture_output=True,
                                    text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS:", result.stdout)


if __name__ == "__main__":
    unittest.main()
