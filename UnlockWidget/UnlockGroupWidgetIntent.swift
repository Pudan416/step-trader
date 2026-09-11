import AppIntents
import WidgetKit

#if !NOWHERE_APP
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Widget"
    static var description: IntentDescription = "Force-refresh widget data."
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedKeys.appGroupId)?.synchronize()
        WidgetKind.reloadAllKinds()
        return .result()
    }
}
#endif

/// Compiled into both targets. The main-app conformance below routes execution
/// into the app process without opening a scene for an already-authorized user.
struct UnlockGroupWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Unlock App Group"
    static var description: IntentDescription = "Spend colors to unlock a feed group for a chosen duration."
    static var isDiscoverable: Bool = false
    @Parameter(title: "Group ID") var groupId: String
    @Parameter(title: "Window") var windowRaw: String

    init() {}
    init(groupId: String, window: AccessWindow) {
        self.groupId = groupId
        self.windowRaw = window.rawValue
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if NOWHERE_APP
        guard !Self.purchaseInFlight else { return .result() }
        Self.purchaseInFlight = true
        defer {
            Self.purchaseInFlight = false
            WidgetCenter.shared.reloadAllTimelines()
        }
        let model = DIContainer.shared.applicationModel
        await model.prepareLocalPurchaseState()
        guard let window = AccessWindow(rawValue: windowRaw),
              let group = model.ticketGroups.first(where: { $0.id == groupId }),
              group.settings.familyControlsModeEnabled,
              group.enabledIntervals.contains(window) else {
            throw WidgetPurchaseFailure(message: String(localized: "Choose an app group"))
        }
        model.familyControlsService.refreshAuthorizationStatus()
        if !model.familyControlsService.isAuthorized {
            do {
                // Already-granted permission can be restored on a cold process
                // without presenting the app. Only an actual permission problem
                // needs foreground continuation.
                try await model.familyControlsService.requestAuthorization()
            } catch {
                try await requestToContinueInForeground()
                try await model.familyControlsService.requestAuthorization()
            }
        }
        model.checkDayBoundary()
        let defaults = SharedKeys.appGroupDefaults()
        let debounceKey = "widgetUnlockLastRequestedAt_\(groupId)"
        if let last = defaults.object(forKey: debounceKey) as? Date,
           Date().timeIntervalSince(last) < 3 { return .result() }
        defaults.set(Date(), forKey: debounceKey)
        guard model.totalStepsBalance >= group.cost(for: window)
                || ShieldRebuildHelper.hasRecoverableUsageBudget(defaults: defaults, groupId: groupId) else {
            throw WidgetPurchaseFailure(message: String(localized: "Not enough colors"))
        }
        model.payGateError = nil
        SharedKeys.recordWidgetInteraction("interactive purchase entered group=\(groupId) authorized=\(model.familyControlsService.isAuthorized)", source: "app")
        guard await model.handlePayGatePaymentForGroup(groupId: groupId, window: window, costOverride: nil) else {
            throw WidgetPurchaseFailure(message: model.payGateError ?? String(localized: "Unable to unlock the app. Please try again."))
        }
        // Persist before returning: Button(intent:) guarantees a timeline reload
        // after perform(), which must observe the committed balance and budget.
        model.writeWidgetSnapshot()
        defaults.synchronize()
        SharedKeys.recordWidgetInteraction("interactive purchase completed group=\(groupId) minutes=\(window.minutes) balance=\(model.totalStepsBalance)", source: "app")
        #else
        // Never execute a second payment implementation in the extension.
        SharedKeys.recordWidgetInteraction("interactive purchase unexpectedly routed to extension", source: "extension")
        throw WidgetPurchaseFailure(message: String(localized: "Open Nowhere to unlock this app."))
        #endif
        return .result()
    }
}

#if NOWHERE_APP
extension UnlockGroupWidgetIntent: ForegroundContinuableIntent {
    @MainActor private static var purchaseInFlight = false
}
#endif

private struct WidgetPurchaseFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
