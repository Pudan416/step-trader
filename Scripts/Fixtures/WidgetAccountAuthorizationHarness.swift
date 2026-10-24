import Foundation

protocol IntentResult {}
struct FixtureResult: IntentResult {}
extension IntentResult where Self == FixtureResult { static func result() -> Self { .init() } }
enum AccessWindow: String, Hashable { case minutes10; var minutes: Int { 10 } }
struct Settings { var familyControlsModeEnabled = true }
struct Group {
    let id = "stable-group"
    var settings = Settings()
    let enabledIntervals: Set<AccessWindow> = [.minutes10]
    func cost(for window: AccessWindow) -> Int { 10 }
}
@MainActor final class Authorization {
    var isAuthorized = false
    var entered: CheckedContinuation<Void, Never>?
    var continuation: CheckedContinuation<Void, Never>?
    var requests = 0
    func refreshAuthorizationStatus() {}
    func requestAuthorization() async throws {
        requests += 1
        await withCheckedContinuation { continuation = $0; entered?.resume(); entered = nil }
        isAuthorized = true
    }
}
@MainActor final class Model {
    var historyWorkGeneration = UUID()
    var isHistoryWorkSuspended = false
    var ticketGroups = [Group()]
    var familyControlsService = Authorization()
    var totalStepsBalance = 100
    var payGateError: String?
    var charges = 0
    var snapshots = 0
    func prepareLocalPurchaseState() async {}
    /*__CURRENT__*/
    func checkDayBoundary() {}
    func handlePayGatePaymentForGroup(groupId: String, window: AccessWindow, costOverride: Int?, recoveryOnly: Bool = false) async -> Bool {
        charges += 1
        totalStepsBalance -= 10
        return true
    }
    func writeWidgetSnapshot() { snapshots += 1 }
}
@MainActor final class DIContainer {
    static let shared = DIContainer()
    var applicationModel = Model()
}
struct WidgetCenter {
    static let shared = WidgetCenter()
    func reloadAllTimelines() {}
}
enum SharedKeys {
    static let suite = "WidgetAccountAuthorization-" + UUID().uuidString
    static let defaults = UserDefaults(suiteName: suite)!
    static func appGroupDefaults() -> UserDefaults { defaults }
    static func recordWidgetInteraction(_ message: String, source: String) {}
}
extension UserDefaults {
    static func nowhere() -> UserDefaults { SharedKeys.defaults }
}
enum ShieldRebuildHelper {
    static func isUsageBudgetActive(defaults: UserDefaults, groupId: String) -> Bool {
        defaults.bool(forKey: "fixtureActivePass_" + groupId)
    }
    static func recoverableUsageBudgetMinutes(defaults: UserDefaults, groupId: String) -> Int { 0 }
    static func hasRecoverableUsageBudget(defaults: UserDefaults, groupId: String) -> Bool { false }
}
struct WidgetPurchaseFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct UnlockGroupWidgetIntent {
    var groupId = "stable-group"
    var windowRaw = "minutes10"
    var recoveryOnly = false
    @MainActor static var purchaseInFlight = false
    func requestToContinueInForeground() async throws {}
    /*__PERFORM__*/
}
@main
struct WidgetAccountAuthorizationHarness {
    @MainActor static func main() async {
        defer { SharedKeys.defaults.removePersistentDomain(forName: SharedKeys.suite) }
        let model = DIContainer.shared.applicationModel
        if CommandLine.arguments.last == "active-pass" {
            model.familyControlsService.isAuthorized = true
            SharedKeys.defaults.set(true, forKey: "fixtureActivePass_stable-group")
            var message: String?
            do { _ = try await UnlockGroupWidgetIntent().perform() }
            catch { message = error.localizedDescription }
            guard message == "This group is already unlocked",
                  model.charges == 0, model.totalStepsBalance == 100,
                  model.snapshots == 0, model.familyControlsService.requests == 0,
                  SharedKeys.defaults.object(forKey: "widgetUnlockLastRequestedAt_stable-group") == nil,
                  !UnlockGroupWidgetIntent.purchaseInFlight else {
                fatalError("an active pass must reject repeat purchase without charging or requesting authorization")
            }
            print("PASS active pass rejects repeat purchase before money or debounce writes")
            return
        }
        let oldGeneration = model.historyWorkGeneration
        var rejected = false
        let attempt = Task {
            do { _ = try await UnlockGroupWidgetIntent().perform() }
            catch { rejected = true }
        }
        await withCheckedContinuation { model.familyControlsService.entered = $0 }
        // A system permission prompt returns only after the local account has
        // become B. Group IDs deliberately match; identity must protect money.
        model.historyWorkGeneration = UUID()
        model.totalStepsBalance = 500
        model.familyControlsService.continuation?.resume()
        await attempt.value
        guard rejected, model.historyWorkGeneration != oldGeneration,
              model.totalStepsBalance == 500, model.charges == 0, model.snapshots == 0 else {
            fatalError("delayed A authorization must not charge B or publish A widget state")
        }
        print("PASS delayed widget authorization cannot charge another account")
    }
}
