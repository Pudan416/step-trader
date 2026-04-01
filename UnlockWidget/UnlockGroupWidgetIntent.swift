import AppIntents
import WidgetKit

// MARK: - Manual Refresh Intent

struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Widget"
    static var description: IntentDescription = "Force-refresh widget data."
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Unlock Intent

/// Interactive intent triggered by widget unlock buttons.
/// Runs entirely in the widget extension process — no app launch required.
struct UnlockGroupWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Unlock App Group"
    static var description: IntentDescription = "Spend colors to unlock a ticket group for a chosen duration."
    static var isDiscoverable: Bool = false

    @Parameter(title: "Group ID")
    var groupId: String

    @Parameter(title: "Window")
    var windowRaw: String

    init() {}

    init(groupId: String, window: AccessWindow) {
        self.groupId = groupId
        self.windowRaw = window.rawValue
    }

    func perform() async throws -> some IntentResult {
        let window = AccessWindow(rawValue: windowRaw) ?? .minutes10
        let cost = Self.cost(for: window)
        let minutes = window.minutes

        let g = UserDefaults(suiteName: SharedKeys.appGroupId) ?? .standard

        let stepsBalance = g.integer(forKey: SharedKeys.stepsBalance)
        let bonusSteps = g.integer(forKey: SharedKeys.bonusSteps)
        let totalBalance = stepsBalance + bonusSteps

        guard totalBalance >= cost else {
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }

        let baseEnergy = g.integer(forKey: SharedKeys.baseEnergyToday)
        let spentToday = g.integer(forKey: SharedKeys.spentStepsToday)

        let consumeFromBase = min(stepsBalance, cost)
        let newSpent = spentToday + consumeFromBase
        let newBalance = max(0, baseEnergy - newSpent)

        g.set(newSpent, forKey: SharedKeys.spentStepsToday)
        g.set(newBalance, forKey: SharedKeys.stepsBalance)

        let remainingCost = max(0, cost - consumeFromBase)
        if remainingCost > 0 {
            let newBonus = max(0, bonusSteps - remainingCost)
            g.set(newBonus, forKey: SharedKeys.bonusSteps)
        }

        let existingBudget = g.integer(forKey: SharedKeys.usageBudgetKey(groupId))
        let totalMinutes = existingBudget + minutes

        g.set(totalMinutes, forKey: SharedKeys.usageBudgetKey(groupId))
        g.set(totalMinutes, forKey: SharedKeys.usageBudgetInitialKey(groupId))
        g.set(Date(), forKey: SharedKeys.usageBudgetStartedKey(groupId))
        g.set(Date().addingTimeInterval(TimeInterval(totalMinutes * 60)), forKey: SharedKeys.usageBudgetExpiryKey(groupId))

        g.set(true, forKey: SharedKeys.pendingBudgetMonitoringPrefix + groupId)
        g.set(totalMinutes, forKey: SharedKeys.pendingBudgetMinutesPrefix + groupId)

        let existingPendingSpend = g.integer(forKey: "pendingSpendAmount_\(groupId)")
        g.set(existingPendingSpend + cost, forKey: "pendingSpendAmount_\(groupId)")
        g.set(true, forKey: "pendingSpendTracking_\(groupId)")

        let updatedBonus = remainingCost > 0 ? max(0, bonusSteps - remainingCost) : bonusSteps
        let prev = WidgetDataFile.read()
        WidgetDataFile.write(WidgetSnapshot(
            balance: newBalance + updatedBonus,
            earned: prev?.earned ?? baseEnergy,
            stepsPoints: prev?.stepsPoints ?? 0,
            sleepPoints: prev?.sleepPoints ?? 0,
            bodyPoints: prev?.bodyPoints ?? 0,
            mindPoints: prev?.mindPoints ?? 0,
            heartPoints: prev?.heartPoints ?? 0,
            timestamp: Date()
        ))

        ShieldRebuildHelper.rebuild()

        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }

    private static func cost(for window: AccessWindow) -> Int {
        TicketGroup.cost(for: window)
    }
}
