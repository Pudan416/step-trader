import AppIntents
import WidgetKit

// MARK: - Manual Refresh Intent

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

        // Debounce: reject rapid duplicate taps (same pattern as ShieldActionExtension)
        let debounceKey = "widgetUnlockLastRequestedAt_\(groupId)"
        let now = Date()
        if let last = g.object(forKey: debounceKey) as? Date,
           now.timeIntervalSince(last) < 3 {
            WidgetKind.reloadAllKinds()
            return .result()
        }
        g.set(now, forKey: debounceKey)

        let dayEndHour = g.object(forKey: SharedKeys.dayEndHour) as? Int ?? 0
        let dayEndMinute = g.object(forKey: SharedKeys.dayEndMinute) as? Int ?? 0
        let anchor = g.object(forKey: SharedKeys.dailyEnergyAnchor) as? Date
        let defaultsStale = DayBoundary.isPersistedDayBehind(
            anchor: anchor, relativeTo: Date(), dayEndHour: dayEndHour, dayEndMinute: dayEndMinute
        )

        let stepsBalance = defaultsStale ? 0 : g.integer(forKey: SharedKeys.stepsBalance)
        let bonusSteps = g.integer(forKey: SharedKeys.bonusSteps)
        let totalBalance = stepsBalance + bonusSteps

        guard totalBalance >= cost else {
            WidgetKind.reloadAllKinds()
            return .result()
        }

        let baseEnergy = defaultsStale ? 0 : g.integer(forKey: SharedKeys.baseEnergyToday)
        let spentToday = defaultsStale ? 0 : g.integer(forKey: SharedKeys.spentStepsToday)

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

        let endOfDay = DayBoundary.nextBoundary(after: Date(), dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
        g.set(endOfDay, forKey: SharedKeys.usageBudgetExpiryKey(groupId))

        g.set(true, forKey: SharedKeys.pendingBudgetMonitoringPrefix + groupId)
        g.set(totalMinutes, forKey: SharedKeys.pendingBudgetMinutesPrefix + groupId)

        let existingPendingSpend = g.integer(forKey: SharedKeys.pendingSpendAmountKey(groupId))
        g.set(existingPendingSpend + cost, forKey: SharedKeys.pendingSpendAmountKey(groupId))
        g.set(true, forKey: SharedKeys.pendingSpendTrackingKey(groupId))

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

        g.synchronize()

        ShieldRebuildHelper.rebuild()

        WidgetKind.reloadAllKinds()

        return .result()
    }

    private static func cost(for window: AccessWindow) -> Int {
        TicketGroup.cost(for: window)
    }
}
